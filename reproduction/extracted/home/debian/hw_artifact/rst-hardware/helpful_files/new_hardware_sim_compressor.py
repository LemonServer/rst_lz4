import random
import json
import argparse
import glob
import os
from itertools import islice, groupby, zip_longest, takewhile
from collections import deque, defaultdict
from dataclasses import dataclass, field
from math import ceil
from typing import List, Tuple, Optional

try:
    from itertools import batched
except ImportError:
    def batched(iterable, n):
        """Compatibility shim for Python < 3.12."""
        if n < 1:
            raise ValueError("n must be at least one")
        iterator = iter(iterable)
        while True:
            batch = tuple(islice(iterator, n))
            if not batch:
                return
            yield batch

# Deterministic randomness for repeatability (not critical for current model)
random.seed(12345)

# ============================================================================
# MetaByte Classes
# ============================================================================

class MetaByte:
    """Base class for bytes in the compression stream"""
    pass


@dataclass
class EncodeDetails:
    raw_bytes: int
    dict_count: int
    dict_bits: int
    compressed_symbols: int
    encoded_bits: int
    dict_bytes: int
    compressed_bytes: int
    dict_lens: List[int] = field(default_factory=list)
    dict_sequences: List[List[int]] = field(default_factory=list)
    compressed_chunk_symbols: List[List[int]] = field(default_factory=list)

class LitByte(MetaByte):
    """Literal byte (0-255)"""
    def __init__(self, value: int):
        assert 0 <= value <= 255
        self.value = value
    
    def __eq__(self, other):
        return isinstance(other, MetaByte) and self.value == other.value
    
    def __lt__(self, other):
        return isinstance(other, MetaByte) and self.value < other.value

    
    def __hash__(self):
        return hash(('lit', self.value))
    
    def __repr__(self):
        return f"Lit({self.value})"
    
    def to_9bit(self) -> str:
        """Return 9-bit representation: 0 + 8 bits for value"""
        return '0' + bin(self.value)[2:].zfill(8)

class CodeByte(MetaByte):
    """Code byte for substitutions (0-62)"""
    def __init__(self, code: int):
        assert 0 <= code <= 62
        self.code = code
        self.value = code + 256
    
    def __eq__(self, other):
        return isinstance(other, MetaByte) and self.value == other.value
    
    def __lt__(self, other):
        return isinstance(other, MetaByte) and self.value < other.value
    
    def __hash__(self):
        return hash(('code', self.code))
    
    def __repr__(self):
        return f"Code({self.code})"
    
    def to_9bit(self) -> str:
        """Return 9-bit representation: 1 + 8 bits for code (padded)"""
        return '1' + bin(self.code)[2:].zfill(8)

# ============================================================================
# Utility Functions
# ============================================================================

def ideal_filter_overlaps(binary, seq_len):
    """Filter overlapping matches"""
    idx = 0
    valid = []
    last_valid = -100
    for idx, num in enumerate(binary):
        if num and idx - last_valid >= seq_len:
            last_valid = idx
            valid.append(1)
        else:
            valid.append(0)
    return valid

def matcher(page: List[MetaByte], seq: Tuple[MetaByte]) -> List[int]:
    """Find matches of sequence in page"""
    matches = []
    for idx in range(len(page)):
        match = 1
        if idx + len(seq) <= len(page):
            for i, s in enumerate(seq):
                if page[idx + i] != s:
                    match = 0
                    break
        else:
            match = 0
        matches.append(match)
    return matches

def sequence_length_to_binary(length: int) -> str:
    """Convert sequence length to 2-bit binary (2->00, 3->01, 4->10, 5->11)"""
    return bin(length - 2)[2:].zfill(2)

def binary_to_sequence_length(binary: str) -> int:
    """Convert 2-bit binary to sequence length"""
    return int(binary, 2) + 2

def sliding_window(iterable, n):
    """Collect data into overlapping fixed-length chunks or blocks."""
    iterator = iter(iterable)
    window = deque(islice(iterator, n - 1), maxlen=n)
    for x in iterator:
        window.append(x)
        yield tuple(window)

def read_file_in_chunks(filename, chunk_size=4096):
    """Read file in fixed-size chunks (pages)."""
    with open(filename, "rb") as file:
        chunk_iter = iter(lambda: file.read(chunk_size), b"")
        return list(takewhile(lambda chunk: chunk, chunk_iter))


def metabytes_to_numeric(symbols: List["MetaByte"]) -> List[int]:
    """Convert MetaByte objects into the 9-bit symbol encoding used by the RTL."""
    return [sym.value for sym in symbols]


def parse_dict_entry_bits(dict_entry: str) -> Tuple[int, List[int]]:
    """Decode a single length-prefixed dictionary-entry bitstring."""
    seq_len = binary_to_sequence_length(dict_entry[:2])
    seq = []
    pos = 2
    for _ in range(seq_len):
        seq.append(int(dict_entry[pos:pos + 9], 2))
        pos += 9
    return seq_len, seq


def parse_dict_entries(subs: List[str]) -> Tuple[List[int], List[List[int]]]:
    """Recover logical dictionary lengths/sequences from the model's entry bitstrings."""
    dict_lens = []
    dict_sequences = []
    for entry in subs:
        seq_len, seq = parse_dict_entry_bits(entry)
        dict_lens.append(seq_len)
        dict_sequences.append(seq)
    return dict_lens, dict_sequences

# ============================================================================
# Update Tracking
# ============================================================================

MAX_SEQ_LEN = 5
DEFAULT_CHUNK_SIZE = 256

CRC_TAPS = (
    (0, 4, 8, 11, 12, 19, 20, 22, 26, 27, 28, 32, 33, 35, 42),
    (1, 5, 9, 12, 13, 20, 21, 23, 27, 28, 29, 33, 34, 36),
    (2, 6, 10, 13, 14, 21, 22, 24, 28, 29, 30, 34, 35, 37),
    (3, 7, 11, 14, 15, 22, 23, 25, 29, 30, 31, 35, 36, 38),
    (4, 8, 12, 15, 16, 23, 24, 26, 30, 31, 32, 36, 37, 39),
    (0, 4, 5, 8, 9, 11, 12, 13, 16, 17, 19, 20, 22, 24, 25, 26, 28, 31, 35, 37, 38, 40, 42),
    (1, 5, 6, 9, 10, 12, 13, 14, 17, 18, 20, 21, 23, 25, 26, 27, 29, 32, 36, 38, 39, 41),
    (2, 6, 7, 10, 11, 13, 14, 15, 18, 19, 21, 22, 24, 26, 27, 28, 30, 33, 37, 39, 40, 42),
    (3, 7, 8, 11, 12, 14, 15, 16, 19, 20, 22, 23, 25, 27, 28, 29, 31, 34, 38, 40, 41),
    (4, 8, 9, 12, 13, 15, 16, 17, 20, 21, 23, 24, 26, 28, 29, 30, 32, 35, 39, 41, 42),
    (5, 9, 10, 13, 14, 16, 17, 18, 21, 22, 24, 25, 27, 29, 30, 31, 33, 36, 40, 42),
    (6, 10, 11, 14, 15, 17, 18, 19, 22, 23, 25, 26, 28, 30, 31, 32, 34, 37, 41),
    (0, 4, 7, 8, 15, 16, 18, 22, 23, 24, 28, 29, 31, 38),
    (1, 5, 8, 9, 16, 17, 19, 23, 24, 25, 29, 30, 32, 39),
    (2, 6, 9, 10, 17, 18, 20, 24, 25, 26, 30, 31, 33, 40),
    (3, 7, 10, 11, 18, 19, 21, 25, 26, 27, 31, 32, 34, 41),
)

def seq_payload_value(seq_len: int, seq: Tuple[MetaByte]) -> int:
    """Match the RTL seq_payload packing used by SeqHasher."""
    values = [0] * MAX_SEQ_LEN
    for idx, sym in enumerate(seq[:MAX_SEQ_LEN]):
        values[idx] = sym.value & 0xFF

    payload = 0
    for value in (values[4], values[3], values[2], values[1], values[0]):
        payload = (payload << 8) | value
    payload = (payload << 3) | (seq_len & 0x7)
    return payload

def rtl_crc16(payload: int) -> int:
    """Exact 16-bit CRC/XOR network used by the RTL hasher."""
    result = 0
    for out_bit, taps in enumerate(CRC_TAPS):
        bit = 0
        for tap in taps:
            bit ^= (payload >> tap) & 1
        result |= (bit << out_bit)
    return result

def find_updates2(pre_replace_idx, post_replace_idx, pre_replace, post_replace, sequence_len):
    """Find increments and decrements from a replacement operation"""
    # Fixed size output arrays
    incs = [None] * 14  # 2+3+4+5
    decs = [None] * 30  # 6+7+8+9

    # Temporary storage
    before_seq = [None] * 4
    after_seq = [None] * 4

    # Fill before_seq from post_replace
    for i in range(4):
        if post_replace_idx - 4 + i >= 0:
            before_seq[i] = post_replace[post_replace_idx - 4 + i]

    # Fill after_seq from pre_replace
    for i in range(4):
        if pre_replace_idx + sequence_len + i < len(pre_replace):
            after_seq[i] = pre_replace[pre_replace_idx + sequence_len + i]

    # Process increments and decrements
    inc_window = before_seq + [post_replace[post_replace_idx]] + after_seq
    
    dec_window = [None] * 13
    for i in range(13):
        if i < 4:
            dec_window[i] = before_seq[i]
        elif i < 9:
            if i < sequence_len + 4:
                dec_window[i] = pre_replace[pre_replace_idx + i - 4]
            else:
                dec_window[i] = after_seq[i - sequence_len - 4]
        else:
            if i - sequence_len < 8:
                dec_window[i] = after_seq[i - sequence_len - 4]
            else:
                dec_window[i] = None

    # incs
    for idx in range(2):
        incs[idx] = inc_window[idx + 3:idx + 5]

    for idx in range(3):
        incs[idx + 2] = inc_window[idx + 2:idx + 5]

    for idx in range(4):
        incs[idx + 5] = inc_window[idx + 1:idx + 5]

    for idx in range(5):
        incs[idx + 9] = inc_window[idx:idx + 5]

    # decs
    for idx in range(6):
        if idx < sequence_len + 1:
            decs[idx] = dec_window[idx + 3:idx + 5]

    for idx in range(7):
        if idx < sequence_len + 2:
            decs[idx + 6] = dec_window[idx + 2:idx + 5]

    for idx in range(8):
        if idx < sequence_len + 3:
            decs[idx + 13] = dec_window[idx + 1:idx + 5]

    for idx in range(9):
        if idx < sequence_len + 4:
            decs[idx + 21] = dec_window[idx:idx + 5]

    # Format output
    for idx, inc in enumerate(incs):
        if inc is None or None in inc:
            incs[idx] = ((), False)
        else:
            incs[idx] = (tuple(inc), True)

    for idx, dec in enumerate(decs):
        if dec is None or None in dec:
            decs[idx] = ((), False)
        else:
            decs[idx] = (tuple(dec), True)

    return incs, decs

# ============================================================================
# Hashing and Aggregation
# ============================================================================

@dataclass(order=True)
class SeqHash:
    """Hash entry for a sequence"""
    banks: int = field(compare=False, repr=False)
    sets_per_bank: int = field(compare=False, repr=False)
    bank_idx: int = field(init=False)
    set_idx: int = field(init=False, compare=False)
    seq_len: int = field(repr=False)
    seq: tuple
    inc: bool
    
    def __post_init__(self):
        hashval = rtl_crc16(seq_payload_value(self.seq_len, self.seq))
        self.bank_idx = hashval % self.banks
        self.set_idx = (hashval // self.banks) % self.sets_per_bank

@dataclass
class AggSeqHash:
    """Aggregated hash entry with count"""
    set_idx: int
    seq_len: int = field(repr=False)
    seq: tuple
    count: int

@dataclass
class TableEntry:
    """One hash-table way, including the explicit valid bit used in RTL."""
    seq: tuple = ()
    count: int = 0
    valid: bool = False

def hash_incs_decs(incs, decs, banks, sets_per_bank):
    """Hash increments and decrements"""
    hashes = []
    for inc in incs:
        if inc[1]:
            hashes.append((True, SeqHash(banks, sets_per_bank, len(inc[0]), inc[0], True)))
        else:
            hashes.append((False, None))

    for dec in decs:
        if dec[1]:
            hashes.append((True, SeqHash(banks, sets_per_bank, len(dec[0]), dec[0], False)))
        else:
            hashes.append((False, None))
    return hashes

def rtl_seq_sort_key(seq):
    """Match SystemVerilog packed seq_t ordering used by SeqSorter.

    seq_t is declared as logic [4:0][8:0], and the sorter compares the packed
    vector numerically. That means seq[4] is the most significant lane and
    seq[0] the least, so Python tuple order must be reversed and zero-padded.
    """
    values = [0] * MAX_SEQ_LEN
    for idx, sym in enumerate(seq[:MAX_SEQ_LEN]):
        values[idx] = sym.value
    return tuple(reversed(values))

def sort_into_banks(hashed_updates):
    """Sort updates into banks"""
    valid_updates = [update for valid, update in hashed_updates if valid]

    if not valid_updates:
        return []

    sorted_updates = sorted(
        valid_updates,
        key=lambda update: (
            update.bank_idx,
            rtl_seq_sort_key(update.seq),
            update.inc,
            update.set_idx,
        ),
    )

    bank_lists = [[] for _ in range(sorted_updates[0].banks)]
    for update in sorted_updates:
        bank_lists[update.bank_idx].append(update)
    return bank_lists

def aggregate(bank_list):
    """Aggregate updates exactly like the RTL SeqAggregator."""
    if not bank_list:
        return []

    aggregated = []
    idx = 0
    while idx < len(bank_list):
        rep_hash = bank_list[idx]
        run_len = 1
        idx += 1

        while idx < len(bank_list):
            next_hash = bank_list[idx]
            if (next_hash.set_idx != rep_hash.set_idx or
                next_hash.seq != rep_hash.seq or
                next_hash.inc != rep_hash.inc):
                break
            run_len += 1
            idx += 1

        count = run_len if rep_hash.inc else -run_len
        aggregated.append(AggSeqHash(rep_hash.set_idx, rep_hash.seq_len, rep_hash.seq, count))

    return aggregated

# ============================================================================
# Hash Table with Sub-tables per Sequence Length
# ============================================================================

class SubTable:
    """Sub-table for a specific sequence length"""
    def __init__(self, seq_len: int, banks: int, sets_per_bank: int, ways: int, fifo_size: int):
        self.seq_len = seq_len
        self.banks = banks
        self.sets_per_bank = sets_per_bank
        self.ways = ways
        self.fifo_size = fifo_size
        
        # Initialize table: [banks][sets][ways] -> (seq, count)
        self.table = []
        for _ in range(banks):
            self.table.append([])
            for _ in range(sets_per_bank):
                self.table[-1].append([TableEntry() for _ in range(ways)])
        
        self.update_fifos = [deque() for _ in range(banks)]
        self.cycles = 0
    
    def inc(self, seq: tuple, count: int, bank_idx: int, set_idx: int):
        """Increment count for sequence using the RTL bank update policy."""
        row = self.table[bank_idx][set_idx]
        match_idx = None
        free_idx = None
        min_idx = 0
        min_count = row[0].count

        for idx, entry in enumerate(row):
            if entry.valid and entry.seq == seq:
                match_idx = idx
            if (not entry.valid) and free_idx is None:
                free_idx = idx
            if not entry.valid:
                min_idx = idx
                min_count = 0
            elif entry.count < min_count:
                min_idx = idx
                min_count = entry.count

        if match_idx is not None:
            next_count = row[match_idx].count + count
            row[match_idx] = TableEntry(
                seq=row[match_idx].seq,
                count=next_count,
                valid=(next_count > 0),
            )
        elif count > 0:
            insert_idx = free_idx if free_idx is not None else min_idx
            row[insert_idx] = TableEntry(seq=seq, count=count, valid=True)

    def dec(self, seq: tuple, count: int, bank_idx: int, set_idx: int):
        """Decrement count for sequence using the RTL bank update policy."""
        row = self.table[bank_idx][set_idx]
        for idx, entry in enumerate(row):
            if entry.valid and entry.seq == seq:
                next_count = entry.count - count
                row[idx] = TableEntry(
                    seq=entry.seq,
                    count=max(0, next_count),
                    valid=(next_count > 0),
                )
                break

    def top(self) -> Tuple[tuple, int]:
        """Get top sequence by count"""
        best = ((), 0)
        for bank in self.table:
            for set_row in bank:
                for entry in set_row:
                    if entry.valid and entry.count > best[1]:
                        best = (entry.seq, entry.count)
        return best

class HashTable:
    """Hash table with separate sub-tables for each sequence length"""
    def __init__(self, config: dict):
        self.config = config
        self.sub_tables = {}
        
        # Throughput and timing knobs
        # update_sites_per_cycle: how many replacement sites per cycle
        self.update_sites_per_cycle = config.get('update_sites_per_cycle', 1)
        # min_cycles_per_iteration: minimum cycles charged per replacement
        # iteration. Represents the number of hardware time-multiplexed chunks.
        # Note: update pipeline depth isn't explicitly modeled here.
        self.min_cycles_per_iteration = config.get('min_cycles_per_iteration', 16)
        # Whether candidate utility should use actual non-overlapping page matches
        # or the hash-table's stored approximate counts. Hardware uses table counts.
        self.top_uses_actual_count = config.get('top_uses_actual_count', False)
        
        # Create sub-table for each sequence length
        for seq_len in [2, 3, 4, 5]:
            key = f"seq_len_{seq_len}"
            st_cfg = config[key]
            self.sub_tables[seq_len] = SubTable(
                seq_len=seq_len,
                banks=st_cfg['banks'],
                sets_per_bank=st_cfg['sets_per_bank'],
                ways=st_cfg['ways'],
                fifo_size=st_cfg['fifo_size']
            )
        
        self.cycles = 0
    
    def reset_cycles(self):
        """Reset cycle counter"""
        self.cycles = 0
        for st in self.sub_tables.values():
            st.cycles = 0
    
    def update(self):
        """Process one cycle of updates from FIFOs"""
        for seq_len, st in self.sub_tables.items():
            for bank_idx, fifo in enumerate(st.update_fifos):
                if fifo:
                    next_elem = fifo.pop()
                    seq, count, set_idx = next_elem.seq, next_elem.count, next_elem.set_idx
                    
                    if count > 0:
                        st.inc(seq, count, bank_idx, set_idx)
                    elif count < 0:
                        st.dec(seq, -count, bank_idx, set_idx)

    def cycle_with_push(self, chunks_by_subtable):
        """Model one hardware cycle with accepted FIFO pushes and normal pops.

        FIFOs decide whether to pop based on whether they were non-empty before
        the cycle's push. Newly pushed data is therefore not visible for pop
        until a later cycle, matching the RTL FIFO behavior.
        """
        pre_nonempty = {}

        for seq_len, next_chunks in chunks_by_subtable.items():
            st = self.sub_tables[seq_len]
            pre_nonempty[seq_len] = [bool(fifo) for fifo in st.update_fifos]

            for bank_idx, chunk in enumerate(next_chunks):
                if bank_idx >= len(st.update_fifos) or not chunk:
                    continue
                st.update_fifos[bank_idx].extendleft(chunk)
                assert len(st.update_fifos[bank_idx]) <= st.fifo_size

        self.cycles += 1

        for seq_len, st in self.sub_tables.items():
            nonempty_before = pre_nonempty.get(seq_len, [False] * len(st.update_fifos))
            for bank_idx, fifo in enumerate(st.update_fifos):
                if bank_idx < len(nonempty_before) and nonempty_before[bank_idx]:
                    next_elem = fifo.pop()
                    seq, count, set_idx = next_elem.seq, next_elem.count, next_elem.set_idx

                    if count > 0:
                        st.inc(seq, count, bank_idx, set_idx)
                    elif count < 0:
                        st.dec(seq, -count, bank_idx, set_idx)
    
    def sequential_update(self, incs, decs):
        """Process updates sequentially with cycle counting"""
        # Group updates by sequence length
        for inc_list, dec_list in zip_longest(incs, decs, fillvalue=[]):
            updates_by_len = {2: [], 3: [], 4: [], 5: []}
            
            # Separate by sequence length - first just collect the raw tuples
            for inc in inc_list:
                if inc[1]:  # if valid
                    seq = inc[0]
                    seq_len = len(seq)
                    if seq_len in updates_by_len:
                        updates_by_len[seq_len].append((seq, True))
            
            for dec in dec_list:
                if dec[1]:  # if valid
                    seq = dec[0]
                    seq_len = len(seq)
                    if seq_len in updates_by_len:
                        updates_by_len[seq_len].append((seq, False))
            
            # Process each sub-table
            max_cycles_to_wait = 0
            all_chunks_by_subtable = {}
            
            for seq_len, raw_updates in updates_by_len.items():
                if not raw_updates:
                    continue
                
                st = self.sub_tables[seq_len]
                
                # Hash with correct bank count for this sub-table
                hashed = []
                for seq, is_inc in raw_updates:
                    new_hash = SeqHash(st.banks, st.sets_per_bank, seq_len, seq, is_inc)
                    hashed.append((True, new_hash))
                
                bank_updates = sort_into_banks(hashed)
                next_chunks = [aggregate(update) for update in bank_updates]
                all_chunks_by_subtable[seq_len] = next_chunks
                
                # Check FIFO space for ALL banks in this sub-table
                cycles_to_wait = 0
                for bank_idx, chunk in enumerate(next_chunks):
                    if bank_idx < len(st.update_fifos):
                        space_in_fifo = st.fifo_size - len(st.update_fifos[bank_idx])
                        space_needed = len(chunk)
                        cycles_to_wait = max(cycles_to_wait, max(0, space_needed - space_in_fifo))
                
                max_cycles_to_wait = max(max_cycles_to_wait, cycles_to_wait)
            
            # Wait for all sub-tables to have space
            for _ in range(max_cycles_to_wait):
                self.each_cycle()
            
            # Now add to FIFOs (should all have space now)
            for seq_len, next_chunks in all_chunks_by_subtable.items():
                st = self.sub_tables[seq_len]
                for bank_idx, chunk in enumerate(next_chunks):
                    if bank_idx < len(st.update_fifos) and chunk:
                        space_available = st.fifo_size - len(st.update_fifos[bank_idx])
                        assert len(chunk) <= space_available

            # Accepted inputs consume one hardware cycle even if no stall was needed.
            self.cycle_with_push(all_chunks_by_subtable)

        # Drain all FIFOs
        max_final_updates = 0
        for st in self.sub_tables.values():
            for fifo in st.update_fifos:
                max_final_updates = max(max_final_updates, len(fifo))
        
        for _ in range(max_final_updates):
            self.each_cycle()
        
        # Verify all FIFOs empty
        for st in self.sub_tables.values():
            for fifo in st.update_fifos:
                assert not fifo
    
    def each_cycle(self):
        """Execute one cycle"""
        self.cycles += 1
        self.update()
    
    def top(self, page: List[MetaByte]) -> Tuple[tuple, float]:
        """Get top sequence across all sub-tables by utility"""
        best_seq = None
        best_utility = -1e9
        
        for seq_len, st in self.sub_tables.items():
            seq, count = st.top()
            if seq:
                # Calculate utility: savings / dict_entry_size
                dict_entry_size = 9 * seq_len + 2
                actual_count = sum(ideal_filter_overlaps(matcher(page, seq), seq_len))
                score_count = actual_count if self.top_uses_actual_count else count
                savings = 9 * (seq_len - 1) * score_count - dict_entry_size
                utility = savings / dict_entry_size if dict_entry_size > 0 else 0
                
                if utility > best_utility:
                    best_utility = utility
                    best_seq = seq
        
        return best_seq, best_utility

    def top_chunked(self, chunks: List[List[MetaByte]]) -> Tuple[tuple, float]:
        """Get top sequence for shared-dictionary chunked pages."""
        best_seq = None
        best_utility = -1e9

        for seq_len, st in self.sub_tables.items():
            seq, count = st.top()
            if seq:
                dict_entry_size = 9 * seq_len + 2
                actual_count = sum(
                    sum(ideal_filter_overlaps(matcher(chunk, seq), seq_len))
                    for chunk in chunks
                )
                score_count = actual_count if self.top_uses_actual_count else count
                savings = 9 * (seq_len - 1) * score_count - dict_entry_size
                utility = savings / dict_entry_size if dict_entry_size > 0 else 0

                if utility > best_utility:
                    best_utility = utility
                    best_seq = seq

        return best_seq, best_utility

# ============================================================================
# Encoding and Compression
# ============================================================================

def apply_pair_replacement(page: List[MetaByte],
                           pattern: Tuple[MetaByte, MetaByte],
                           code_mb: MetaByte) -> List[MetaByte]:
    """Apply a simple non-overlapping left-to-right 2-byte -> 1-byte replacement."""
    new_page = []
    i = 0
    n = len(page)
    while i < n:
        if i + 1 < n and page[i] == pattern[0] and page[i + 1] == pattern[1]:
            new_page.append(code_mb)
            i += 2
        else:
            new_page.append(page[i])
            i += 1
    return new_page

def split_page_chunks(page: List[MetaByte], chunk_size: int) -> List[List[MetaByte]]:
    """Split a page into fixed-size chunks for page-wrapper-accurate modeling."""
    if chunk_size <= 0:
        return [list(page)]
    return [list(page[idx:idx + chunk_size]) for idx in range(0, len(page), chunk_size)]

def flatten_page_chunks(chunks: List[List[MetaByte]]) -> List[MetaByte]:
    """Flatten chunked page representation back into one symbol stream."""
    return [mb for chunk in chunks for mb in chunk]

def total_chunk_symbols(chunks: List[List[MetaByte]]) -> int:
    """Count total meta-symbols across all chunks."""
    return sum(len(chunk) for chunk in chunks)

def apply_pair_replacement_chunks(chunks: List[List[MetaByte]],
                                  pattern: Tuple[MetaByte, MetaByte],
                                  code_mb: MetaByte) -> List[List[MetaByte]]:
    """Apply a fixed replacement independently within each chunk."""
    return [apply_pair_replacement(chunk, pattern, code_mb) for chunk in chunks]

def make_replacements(hash_table: HashTable, page: List[MetaByte], 
                     seq: tuple, code: CodeByte) -> Tuple[List[MetaByte], int]:
    """Make replacements and update hash table
    
    For each replacement site, generates exactly 44 updates:
    - 2 two-byte increments, 3 three-byte increments, 4 four-byte increments, 5 five-byte increments
    - 6 two-byte decrements, 7 three-byte decrements, 8 four-byte decrements, 9 five-byte decrements
    All 44 updates are pushed to the update pipeline in one cycle (unless FIFOs stall).
    """
    matches = matcher(page, seq)
    filtered_matches = ideal_filter_overlaps(matches, len(seq))
    new_page = []
    pre_replace_indices = []
    post_replace_indices = []
    
    for idx, (byte, true_match) in enumerate(zip(page, filtered_matches)):
        if true_match:
            pre_replace_indices.append(idx)
            post_replace_indices.append(len(new_page))
            new_page.append(code)
        elif not any(filtered_matches[max(0, idx - len(seq) + 1):idx]):
            new_page.append(byte)
    
    incs, decs = [], []
    for pre_idx, post_idx in zip(pre_replace_indices, post_replace_indices):
        inc, dec = find_updates2(pre_idx, post_idx, page, new_page, len(seq))
        incs.append(inc)
        decs.append(dec)
    
    # Group multiple replacement sites per cycle according to the config
    sites_per_cycle = getattr(hash_table, 'update_sites_per_cycle', 1)
    batched_incs = []
    batched_decs = []

    for i in range(0, len(incs), sites_per_cycle):
        inc_batch = []
        dec_batch = []
        for inc_site, dec_site in zip(incs[i:i + sites_per_cycle], decs[i:i + sites_per_cycle]):
            inc_batch.extend(inc_site)
            dec_batch.extend(dec_site)
        batched_incs.append(inc_batch)
        batched_decs.append(dec_batch)

    hash_table.reset_cycles()
    hash_table.sequential_update(batched_incs, batched_decs)
    
    return new_page, hash_table.cycles

def init_count_chunked(hash_table: HashTable, chunks: List[List[MetaByte]]) -> int:
    """Run initial counting chunk-by-chunk with drain between chunks."""
    total_cycles = 0
    updates_per_len_per_cycle = hash_table.update_sites_per_cycle * 8

    for chunk in chunks:
        incs_by_len = {seq_len: [] for seq_len in range(2, MAX_SEQ_LEN + 1)}

        for start in range(len(chunk)):
            for seq_len in range(2, MAX_SEQ_LEN + 1):
                end = start + seq_len
                if end <= len(chunk):
                    seq = tuple(chunk[start:end])
                    incs_by_len[seq_len].append((seq, True))

        batched_incs = []
        idx_by_len = {seq_len: 0 for seq_len in incs_by_len}

        while any(idx_by_len[seq_len] < len(incs_by_len[seq_len]) for seq_len in incs_by_len):
            cycle_batch = []
            for seq_len in range(2, MAX_SEQ_LEN + 1):
                lst = incs_by_len[seq_len]
                idx = idx_by_len[seq_len]
                remaining = len(lst) - idx
                if remaining <= 0:
                    continue
                take = min(updates_per_len_per_cycle, remaining)
                cycle_batch.extend(lst[idx:idx + take])
                idx_by_len[seq_len] += take

            if cycle_batch:
                batched_incs.append(cycle_batch)

        hash_table.reset_cycles()
        hash_table.sequential_update(batched_incs, [])
        total_cycles += hash_table.cycles

    return total_cycles

def make_replacements_chunked(hash_table: HashTable, chunks: List[List[MetaByte]],
                              seq: tuple, code: CodeByte) -> Tuple[List[List[MetaByte]], int]:
    """Apply a substitution iteration chunk-by-chunk with shared hash state."""
    new_chunks = []
    total_cycles = 0

    for chunk in chunks:
        new_chunk, chunk_cycles = make_replacements(hash_table, chunk, seq, code)
        new_chunks.append(new_chunk)
        total_cycles += chunk_cycles

    return new_chunks, total_cycles

def cram_iteration(page: List[MetaByte], hash_table: HashTable, 
                   next_code: int) -> Tuple[str, List[MetaByte], int]:
    """Perform one CRAM iteration"""
    if next_code > 62:
        return "", page, 0
    
    top_seq, utility = hash_table.top(page)
    if not top_seq or utility <= 0:
        return "", page, 0
    
    code = CodeByte(next_code)
    new_page, cycles = make_replacements(hash_table, page, top_seq, code)
    
    # Check if beneficial
    dict_entry_size = 9 * len(top_seq) + 2
    if len(new_page) + (dict_entry_size / 9) >= len(page):
        # Not worth it; model as no additional work for this rejected iteration.
        return "", page, 0
    
    # Enforce minimum cycles per successful iteration
    min_iter_cycles = getattr(hash_table, 'min_cycles_per_iteration', 0)
    effective_cycles = max(cycles, min_iter_cycles)
    
    # Encode dictionary entry
    length_bits = sequence_length_to_binary(len(top_seq))
    seq_bits = "".join(mb.to_9bit() for mb in top_seq)
    dict_entry = length_bits + seq_bits
    
    return dict_entry, new_page, effective_cycles

def cram_iteration_chunked(chunks: List[List[MetaByte]], hash_table: HashTable,
                           next_code: int) -> Tuple[str, List[List[MetaByte]], int]:
    """Perform one shared-dictionary chunked CRAM iteration."""
    if next_code > 62:
        return "", chunks, 0

    top_seq, utility = hash_table.top_chunked(chunks)
    if not top_seq or utility <= 0:
        return "", chunks, 0

    code = CodeByte(next_code)
    new_chunks, cycles = make_replacements_chunked(hash_table, chunks, top_seq, code)

    dict_entry_size = 9 * len(top_seq) + 2
    if total_chunk_symbols(new_chunks) + (dict_entry_size / 9) >= total_chunk_symbols(chunks):
        return "", chunks, 0

    min_iter_cycles = getattr(hash_table, 'min_cycles_per_iteration', 0)
    effective_cycles = max(cycles, min_iter_cycles)

    length_bits = sequence_length_to_binary(len(top_seq))
    seq_bits = "".join(mb.to_9bit() for mb in top_seq)
    dict_entry = length_bits + seq_bits

    return dict_entry, new_chunks, effective_cycles

def cram_encode_contiguous(page_bytes: bytes, config: dict,
                           return_details: bool = False):
    """Encode a page as one contiguous stream."""
    memory_blocks = config.get('memory_blocks', 2)
    static_tree_codes_per_cycle = config.get('static_tree_codes_per_cycle', 8)
    min_iter_cycles = config.get('min_cycles_per_iteration', 16)
    apply_free_substitutions = config.get('apply_free_substitutions', False)

    page = [LitByte(b) for b in page_bytes]
    total_cycles = 0

    if apply_free_substitutions:
        page = apply_pair_replacement(page, (LitByte(0), LitByte(0)), CodeByte(0))
        total_cycles += min_iter_cycles

        page = apply_pair_replacement(page, (CodeByte(0), CodeByte(0)), CodeByte(1))
        total_cycles += min_iter_cycles

    hash_table = HashTable(config)

    incs_by_len = {seq_len: [] for seq_len in range(2, MAX_SEQ_LEN + 1)}

    for start in range(len(page)):
        for seq_len in range(2, MAX_SEQ_LEN + 1):
            end = start + seq_len
            if end <= len(page):
                seq = tuple(page[start:end])
                incs_by_len[seq_len].append((seq, True))

    updates_per_len_per_cycle = hash_table.update_sites_per_cycle * 8

    batched_incs = []
    idx_by_len = {seq_len: 0 for seq_len in incs_by_len}

    while any(idx_by_len[seq_len] < len(incs_by_len[seq_len]) for seq_len in incs_by_len):
        cycle_batch = []
        for seq_len in range(2, MAX_SEQ_LEN + 1):
            lst = incs_by_len[seq_len]
            idx = idx_by_len[seq_len]
            remaining = len(lst) - idx
            if remaining <= 0:
                continue
            take = min(updates_per_len_per_cycle, remaining)
            cycle_batch.extend(lst[idx:idx + take])
            idx_by_len[seq_len] += take

        if cycle_batch:
            batched_incs.append(cycle_batch)

    hash_table.sequential_update(batched_incs, [])
    total_cycles += hash_table.cycles

    subs = []
    compressed = page
    total_bits = memory_blocks * 64 * 8 - 6
    next_code = 0

    while next_code <= 62:
        old = compressed
        dict_entry, compressed, cycles = cram_iteration(compressed, hash_table, next_code)
        total_cycles += cycles

        if not dict_entry or total_bits - len(dict_entry) < 0:
            compressed = old
            break

        total_bits -= len(dict_entry)
        subs.append(dict_entry)
        next_code += 1

    count_bits = bin(len(subs))[2:].zfill(6)
    dict_bits = count_bits + "".join(subs)

    min_bytes = ceil(len(dict_bits) / 8)
    dict_bytes = bytes(
        int("".join(num), 2)
        for num in batched(dict_bits.ljust(8 * min_bytes, "0"), 8)
    )

    compressed_bits = "".join(mb.to_9bit() for mb in compressed)
    compressed_min_bytes = ceil(len(compressed_bits) / 8)
    compressed_bytes = bytes(
        int("".join(num), 2)
        for num in batched(compressed_bits.ljust(8 * compressed_min_bytes, "0"), 8)
    )

    result = dict_bytes + compressed_bytes

    if static_tree_codes_per_cycle > 0:
        total_symbols = len(compressed)
        static_cycles = ceil(total_symbols / static_tree_codes_per_cycle)
        total_cycles += static_cycles

    if return_details:
        dict_lens, dict_sequences = parse_dict_entries(subs)
        details = EncodeDetails(
            raw_bytes=len(page_bytes),
            dict_count=len(subs),
            dict_bits=len(dict_bits),
            compressed_symbols=len(compressed),
            encoded_bits=len(dict_bits) + 9 * len(compressed),
            dict_bytes=len(dict_bytes),
            compressed_bytes=len(compressed_bytes),
            dict_lens=dict_lens,
            dict_sequences=dict_sequences,
            compressed_chunk_symbols=[metabytes_to_numeric(compressed)],
        )
        return result, total_cycles, details

    return result, total_cycles

def cram_encode_chunked(page_bytes: bytes, config: dict,
                        return_details: bool = False):
    """Encode a page using shared-dictionary 256B chunk semantics."""
    memory_blocks = config.get('memory_blocks', 2)
    static_tree_codes_per_cycle = config.get('static_tree_codes_per_cycle', 8)
    min_iter_cycles = config.get('min_cycles_per_iteration', 16)
    apply_free_substitutions = config.get('apply_free_substitutions', False)
    chunk_size = config.get('chunk_size', DEFAULT_CHUNK_SIZE)

    page = [LitByte(b) for b in page_bytes]
    chunks = split_page_chunks(page, chunk_size)
    total_cycles = 0

    if apply_free_substitutions:
        chunks = apply_pair_replacement_chunks(chunks, (LitByte(0), LitByte(0)), CodeByte(0))
        total_cycles += min_iter_cycles

        chunks = apply_pair_replacement_chunks(chunks, (CodeByte(0), CodeByte(0)), CodeByte(1))
        total_cycles += min_iter_cycles

    hash_table = HashTable(config)
    total_cycles += init_count_chunked(hash_table, chunks)

    subs = []
    compressed_chunks = chunks
    total_bits = memory_blocks * 64 * 8 - 6
    next_code = 0

    while next_code <= 62:
        old_chunks = compressed_chunks
        dict_entry, compressed_chunks, cycles = cram_iteration_chunked(compressed_chunks, hash_table, next_code)
        total_cycles += cycles

        if not dict_entry or total_bits - len(dict_entry) < 0:
            compressed_chunks = old_chunks
            break

        total_bits -= len(dict_entry)
        subs.append(dict_entry)
        next_code += 1

    count_bits = bin(len(subs))[2:].zfill(6)
    dict_bits = count_bits + "".join(subs)

    min_bytes = ceil(len(dict_bits) / 8)
    dict_bytes = bytes(
        int("".join(num), 2)
        for num in batched(dict_bits.ljust(8 * min_bytes, "0"), 8)
    )

    compressed_bits = "".join(mb.to_9bit() for mb in flatten_page_chunks(compressed_chunks))
    compressed_min_bytes = ceil(len(compressed_bits) / 8)
    compressed_bytes = bytes(
        int("".join(num), 2)
        for num in batched(compressed_bits.ljust(8 * compressed_min_bytes, "0"), 8)
    )

    result = dict_bytes + compressed_bytes

    if static_tree_codes_per_cycle > 0:
        total_symbols = total_chunk_symbols(compressed_chunks)
        static_cycles = ceil(total_symbols / static_tree_codes_per_cycle)
        total_cycles += static_cycles

    if return_details:
        compressed_symbols = total_chunk_symbols(compressed_chunks)
        dict_lens, dict_sequences = parse_dict_entries(subs)
        details = EncodeDetails(
            raw_bytes=len(page_bytes),
            dict_count=len(subs),
            dict_bits=len(dict_bits),
            compressed_symbols=compressed_symbols,
            encoded_bits=len(dict_bits) + 9 * compressed_symbols,
            dict_bytes=len(dict_bytes),
            compressed_bytes=len(compressed_bytes),
            dict_lens=dict_lens,
            dict_sequences=dict_sequences,
            compressed_chunk_symbols=[
                metabytes_to_numeric(chunk) for chunk in compressed_chunks
            ],
        )
        return result, total_cycles, details

    return result, total_cycles

def cram_encode(page_bytes: bytes, config: dict,
                return_details: bool = False):
    """Encode a page using CRAM.

    Defaults to the hardware page-wrapper semantics:
    - 256B chunks
    - shared dictionary across the page
    - no cross-chunk sequence matches
    - no free substitutions unless explicitly enabled

    This intentionally models the current RTL baseline rather than the full
    `third_party/cram_cpp/cram_impl.cpp` feature set. In particular, the C++
    path also has extra ratio boosters such as forced early substitutions and
    reuse codes 63..70 in dictionary/chunk encoding.
    """
    chunk_size = config.get('chunk_size', DEFAULT_CHUNK_SIZE)
    if chunk_size is None or chunk_size <= 0:
        return cram_encode_contiguous(page_bytes, config, return_details=return_details)
    return cram_encode_chunked(page_bytes, config, return_details=return_details)

# ============================================================================
# Benchmarking
# ============================================================================

def run_benchmark(filepath: str, config: dict) -> dict:
    """Run benchmark on a dataset file path"""
    num_pages = config.get('pages_per_benchmark', 100)
    
    pages = read_file_in_chunks(filepath)
    sample = pages[:num_pages]
    
    results = {
        'benchmark_file': os.path.basename(filepath),
        'pages_processed': 0,
        'total_cycles': 0,
        'total_original_size': 0,
        'total_compressed_size': 0,
        'compression_ratios': []
    }
    
    for page in sample:
        try:
            original_size = len(page)
            compressed, cycles = cram_encode(page, config)
            compressed_size = len(compressed)
            
            results['pages_processed'] += 1
            results['total_cycles'] += cycles
            results['total_original_size'] += original_size
            results['total_compressed_size'] += compressed_size
            results['compression_ratios'].append(original_size / compressed_size)
        except Exception as e:
            print(f"Error processing page in {filepath}: {e}")
            continue
    
    if results['pages_processed'] > 0:
        results['avg_cycles_per_page'] = results['total_cycles'] / results['pages_processed']
        results['overall_compression_ratio'] = results['total_original_size'] / results['total_compressed_size']
    
    return results

def main():
    """Main entry point.
    
    Expects three command line arguments:
      1) config_path: path to JSON config file
      2) input_dir: directory containing benchmark files
      3) output_path: path to JSON file where results will be written

    The output JSON embeds the config and a dict of benchmark results keyed
    by file name.
    """
    parser = argparse.ArgumentParser(description="CRAM encoder benchmark driver")
    parser.add_argument("config_path", help="Path to JSON configuration file")
    parser.add_argument("input_dir", help="Directory containing benchmark files")
    parser.add_argument("output_path", help="Path to output JSON results file")
    args = parser.parse_args()

    # Load configuration (can include small description strings for parameters)
    with open(args.config_path, "r") as cf:
        config = json.load(cf)
    
    all_results = {'config': config, 'benchmarks': {}}
    
    # Use glob to iterate over all files in the input directory
    pattern = os.path.join(args.input_dir, "*")
    for filepath in sorted(glob.glob(pattern)):
        if not os.path.isfile(filepath):
            continue
        label = os.path.basename(filepath)
        print(f"Running {label}...")
        result = run_benchmark(filepath, config)
        all_results['benchmarks'][label] = result
        print(f"  Processed: {result['pages_processed']} pages")
        print(f"  Avg cycles: {result.get('avg_cycles_per_page', 0):.2f}")
        print(f"  Compression ratio: {result.get('overall_compression_ratio', 0):.4f}")
    
    # Write results
    with open(args.output_path, 'w') as f:
        json.dump(all_results, f, indent=2)
    
    print(f"\nResults written to {args.output_path}")

if __name__ == "__main__":
    main()
