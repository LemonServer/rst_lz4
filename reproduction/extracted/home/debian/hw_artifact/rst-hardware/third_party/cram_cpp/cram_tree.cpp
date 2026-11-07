#include "cram_tree.h"

// Define static members for LitByte:
LitByte* LitByte::instances_[256] = { 0 };
bool LitByte::s_initialized = false;

void LitByte::initializeAll() {
    for (int i = 0; i < 256; i++) {
        instances_[i] = new LitByte(i);
    }
    s_initialized = true;
}

// Define static members for CRAMSub:
CRAMSub* CRAMSub::instances_[EXTENDED_CRAMSUB] = { 0 };
bool CRAMSub::s_initialized = false;

void CRAMSub::initializeAll() {
    for (int i = 0; i < EXTENDED_CRAMSUB; i++) {
        instances_[i] = new CRAMSub(i);
    }
    s_initialized = true;
}