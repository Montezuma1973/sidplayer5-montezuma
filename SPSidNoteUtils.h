#ifndef SPSidNoteUtils_h
#define SPSidNoteUtils_h

#include <stdint.h>

struct SPSidNoteMapEntry
{
    uint16_t frequency;
    const char *noteString;
};

static const int sSPSidNoteCount = 8 * 12;

// taken from JCH's player...
static const struct SPSidNoteMapEntry sSPSidNoteMap[sSPSidNoteCount] =
{
    { 0x0116, "C-1" }, { 0x0127, "C#1" }, { 0x0138, "D-1" }, { 0x014b, "D#1" }, { 0x015f, "E-1" }, { 0x0173, "F-1" }, { 0x018a, "F#1" }, { 0x01a1, "G-1" }, { 0x01ba, "G#1" }, { 0x01d4, "A-1" }, { 0x01f0, "A#1" }, { 0x020e, "B-1" },
    { 0x022d, "C-2" }, { 0x024e, "C#2" }, { 0x0271, "D-2" }, { 0x0296, "D#2" }, { 0x02bd, "E-2" }, { 0x02e7, "F-2" }, { 0x0313, "F#2" }, { 0x0342, "G-2" }, { 0x0374, "G#2" }, { 0x03a9, "A-2" }, { 0x03e0, "A#2" }, { 0x041b, "B-2" },
    { 0x045a, "C-3" }, { 0x049b, "C#3" }, { 0x04e2, "D-3" }, { 0x052c, "D#3" }, { 0x057b, "E-3" }, { 0x05ce, "F-3" }, { 0x0627, "F#3" }, { 0x0685, "G-3" }, { 0x06e8, "G#3" }, { 0x0751, "A-3" }, { 0x07c1, "A#3" }, { 0x0837, "B-3" },
    { 0x08b4, "C-4" }, { 0x0937, "C#4" }, { 0x09c4, "D-4" }, { 0x0a57, "D#4" }, { 0x0af5, "E-4" }, { 0x0b9c, "F-4" }, { 0x0c4e, "F#4" }, { 0x0d09, "G-4" }, { 0x0dd0, "G#4" }, { 0x0ea3, "A-4" }, { 0x0f82, "A#4" }, { 0x106e, "B-4" },
    { 0x1168, "C-5" }, { 0x126e, "C#5" }, { 0x1388, "D-5" }, { 0x14af, "D#5" }, { 0x15eb, "E-5" }, { 0x1739, "F-5" }, { 0x189c, "F#5" }, { 0x1a13, "G-5" }, { 0x1ba1, "G#5" }, { 0x1d46, "A-5" }, { 0x1f04, "A#5" }, { 0x20dc, "B-5" },
    { 0x22d0, "C-6" }, { 0x24dc, "C#6" }, { 0x2710, "D-6" }, { 0x295e, "D#6" }, { 0x2bd6, "E-6" }, { 0x2e72, "F-6" }, { 0x3138, "F#6" }, { 0x3426, "G-6" }, { 0x3742, "G#6" }, { 0x3a8c, "A-6" }, { 0x3e08, "A#6" }, { 0x41b8, "B-6" },
    { 0x45a0, "C-7" }, { 0x49b8, "C#7" }, { 0x4e20, "D-7" }, { 0x52bc, "D#7" }, { 0x57ac, "E-7" }, { 0x5ce4, "F-7" }, { 0x6270, "F#7" }, { 0x684c, "G-7" }, { 0x6e84, "G#7" }, { 0x7518, "A-7" }, { 0x7c10, "A#7" }, { 0x8370, "B-7" },
    { 0x8b40, "C-8" }, { 0x9370, "C#8" }, { 0x9c40, "D-8" }, { 0xa578, "D#8" }, { 0xaf58, "E-8" }, { 0xb9c8, "F-8" }, { 0xc4e0, "F#8" }, { 0xd098, "G-8" }, { 0xdd08, "G#8" }, { 0xea30, "A-8" }, { 0xf820, "A#8" }, { 0xfd2e, "B-8" },
};

static const char *SPSidNoteStringForFrequency(uint16_t frequency)
{
    int lowerstep;
    int higherstep;

    for (int i = 0; i < sSPSidNoteCount; i++)
    {
        lowerstep = (i > 0) ? (sSPSidNoteMap[i].frequency - sSPSidNoteMap[i - 1].frequency) : sSPSidNoteMap[i].frequency;
        higherstep = (i < (sSPSidNoteCount - 1)) ? (sSPSidNoteMap[i + 1].frequency - sSPSidNoteMap[i].frequency) : (0xffff - sSPSidNoteMap[i].frequency);

        if (frequency >= (sSPSidNoteMap[i].frequency - lowerstep / 2) && frequency < (sSPSidNoteMap[i].frequency + higherstep / 2))
            return sSPSidNoteMap[i].noteString;
    }

    return "";
}

#endif
