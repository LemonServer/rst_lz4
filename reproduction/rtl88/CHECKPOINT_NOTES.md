The initial per-stage JSON checkpoint wrapper could not encode raw_pages bytes.
This wrapper failure occurs after run_hardware_roundtrip returns and writes its
actual RTL log. It is not an RTL verdict. The fixed driver uses pickle for local
checkpoints and may reuse a completed RTL log only when the explicit testbench
pass marker is present and the parsed page count equals the requested actual
count. Input files and RTL executables are unchanged. All other stages still run.
The current first pass is allowed to finish so ongoing simulations are retained;
the fixed driver then reuses verified logs and completes the remaining stages.

A follow-on supervisor advances datasets whose original hardware roundtrip has
finished. It does not interrupt pending original simulations. Per-dataset flock
locks prevent two corrected workers from processing the same dataset concurrently;
checkpoints and final JSON are replaced atomically. All requested pages and all
three verification stages remain required. Eligible completed logs are discovered
every ten minutes. The final main driver uses the same locks and cached results.
