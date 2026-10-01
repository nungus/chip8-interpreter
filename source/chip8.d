import std.algorithm.searching : countUntil;
import std.conv : to;
import std.file;
import std.random;


const int ROM_MEMORY_BEGIN = 0x200;
const int MEMORY_END = 0xFFF;
const ubyte INSTR_SIZE = 2;
const int LOGICAL_WIDTH = 64;
const int LOGICAL_HEIGHT = 32;

struct Framebuffer {
	const BITMAP_W_BYTES = 8;
	const BITMAP_H_PX = 32;
	ubyte[BITMAP_W_BYTES][BITMAP_H_PX] bitmap;

	string bitmapPretty() {
		string pretty = "";
		foreach (row; bitmap) {
			foreach (j; row) {
				for (auto b = 7; b >= 0; b--) {
					pretty ~= ((j >> b) & 1 ? "#" : ".") ~ " ";
				}
			}
			pretty ~= "\n";
		}
		return pretty;
	}

	void cls() {
		for (int i = 0; i < BITMAP_H_PX; i++) {
		    for (int j = 0; j < BITMAP_W_BYTES; j++) {
				bitmap[i][j] = 0;
			}
		}
	}

	// Draw a sprite with a width of 8 pixels. This project uses a packed bitmap
	// and sprites are not necessarily byte-aligned, so we must account for
	// left and right bytes which may be updated when it is drawn.
	// Return true if any pixel erasure occurs. (Pixel erasure: XORing the
	// sprite onto the screen causes a pixel to change from 1 -> 0.)
	bool drawSprite(ubyte[] sprBytes, ubyte x, ubyte y) {
        x %= LOGICAL_WIDTH;
        y %= LOGICAL_HEIGHT;
		ubyte xByteLeft = x / 8;
		ubyte xByteRight = cast(ubyte) (xByteLeft + 1);
		ubyte xByteOffset = x % 8;
		bool causedPixelErasure = 0;
		for (int i = 0; i < sprBytes.length && y + i < LOGICAL_HEIGHT; i++) {
			auto y_i = y + i;

			// Left
			ubyte sprByteLeft = sprBytes[i] >> xByteOffset;
			causedPixelErasure |= (bitmap[y_i][xByteLeft] & sprByteLeft) != 0;
			bitmap[y_i][xByteLeft] ^= sprByteLeft;

			// Right
            if (xByteRight < BITMAP_W_BYTES) {
                ubyte sprByteRight = cast(ubyte) (sprBytes[i] << (8 - xByteOffset));
                causedPixelErasure |= (bitmap[y_i][xByteRight] & sprByteRight) != 0;
                bitmap[y_i][xByteRight] ^= sprByteRight;
            }
		}
		return causedPixelErasure;
	}
}

struct IOState {
	bool keepExecuting = true;
    bool displayDirty = false; // Set when bitmap is modified with Dxyn. Purpose is to signal a display update. NOT cleared by the CHIP-8.
	ubyte[16] keyDown; // 1 when down, 0 when up.
	ubyte ST; // Sound timer.

    // Default values cater to the original COSMAC VIP configuration.
    bool useLegacyIncrement_I = true;
    bool useLegacySetVxToVy = true;
    bool useLegacySpriteInterrupt = true;
}

struct Chip8 {
	ubyte[4096] memory = initMem(); // 0x000 -> 0x1FF: Location of original interpreter.
	ubyte[16] V; // Registers.
	ushort I;
    ubyte DT; // Delay timer.
	ushort PC = ROM_MEMORY_BEGIN;
	byte SP = -1;
	ushort[16] stack;

	Framebuffer fb;
	IOState ioState;
    bool interruptOccurred = false;

	Random rnd;

    static const ubyte[80] digitData = [
        0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
        0x20, 0x60, 0x20, 0x20, 0x70, // 1
        0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
        0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
        0x90, 0x90, 0xF0, 0x10, 0x10, // 4
        0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
        0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
        0xF0, 0x10, 0x20, 0x40, 0x40, // 7
        0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
        0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
        0xF0, 0x90, 0xF0, 0x90, 0x90, // A
        0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
        0xF0, 0x80, 0x80, 0x80, 0xF0, // C
        0xE0, 0x90, 0x90, 0x90, 0xE0, // D
        0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
        0xF0, 0x80, 0xF0, 0x80, 0x80, // F
    ];

    private static ubyte[4096] initMem() {
        ubyte[4096] mem;
        mem[0 .. digitData.sizeof] = digitData[];
        return mem;
    }

    static Chip8 create() {
        Chip8 chip;
        chip.rnd = Random(unpredictableSeed);
        // Memory is initialised statically.
        return chip;
    }

	private void stackPush(ushort value) {
		stack[++SP] = value;
	}
	private ushort stackPop() {
		return stack[SP--];
	}

	// Fetch-Decode-Execute the instruction currently pointed to by the PC.
	void executeInstruction() {
		ushort opcode = (memory[PC] << 8) | (memory[PC + 1]);
		
		ubyte x = (opcode & 0xF00) >> 8;
		ubyte y = (opcode & 0xF0) >> 4;
		ushort nnn = opcode & 0xFFF;
		ubyte kk = opcode & 0xFF;
		ubyte n = opcode & 0xF;

		// TODO: maybe document instructions...
		switch (opcode & 0xF000) {
			case 0x0000:
				switch (nnn) {
					case 0x0E0:
						fb.cls();
                        ioState.displayDirty = true;
						break;
					case 0x0EE:
						PC = stackPop();
						return;
					default:
						// 0nnn case. Do nothing.
				}
				break;
			case 0x1000:
				PC = nnn;
				return;
			case 0x2000:
				PC += INSTR_SIZE;
				stackPush(PC);
				PC = nnn;
				return;
			case 0x3000:
				if (V[x] == kk) {
					PC += INSTR_SIZE;
				}
				break;
			case 0x4000:
				if (V[x] != kk) {
					PC += INSTR_SIZE;
				}
				break;
			case 0x5000:
				if (V[x] == V[y]) {
					PC += INSTR_SIZE;
				}
				break;
			case 0x6000:
				V[x] = kk;
				break;
			case 0x7000:
				V[x] += kk;
				break;
			case 0x8000:
				switch (n) {
					case 0:
						V[x] = V[y];
						break;
					case 1:
						V[x] |= V[y];
                        V[0xF] = 0;
						break;
					case 2:
						V[x] &= V[y];
                        V[0xF] = 0;
						break;
					case 3:
						V[x] ^= V[y];
                        V[0xF] = 0;
						break;
					case 4:
						auto sum = V[x] + V[y];
						V[x] = cast(ubyte) sum;
						V[0xF] = sum > 255;
						break;
					case 5:
						bool flag = V[x] >= V[y];
						V[x] -= V[y];
                        V[0xF] = flag;
						break;
					case 6:
                        if (ioState.useLegacySetVxToVy) V[x] = V[y];
						bool flag = V[x] & 1;
						V[x] >>= 1;
                        V[0xF] = flag;
						break;
					case 7:
						bool flag = V[y] >= V[x];
						V[x] = cast(ubyte) (V[y] - V[x]);
						V[0xF] = flag; 
                        break;
					case 0xE:
                        if (ioState.useLegacySetVxToVy) V[x] = V[y];
						bool flag = (V[x] >> 7) & 1;
						V[x] <<= 1;
						V[0xF] = flag;
                        break;
					default:
						throw new Exception("Unrecognised 8-instruction.");
				}
				break;
			case 0x9000:
				if (V[x] != V[y]) {
					PC += INSTR_SIZE;
				}
				break;
			case 0xA000:
				I = nnn;
				break;
			case 0xB000:
				PC = cast(ushort) (nnn + V[0]);
				return;
			case 0xC000:
				V[x] = kk & uniform(0, 256, rnd);
				break;
			case 0xD000:
                if (ioState.useLegacySpriteInterrupt && !interruptOccurred) {
                    // Do not allow sprite drawing until the next interrupt occurs.
                    return;
                }
				V[0xF] = fb.drawSprite(memory[I .. I + n], V[x], V[y]);
                ioState.displayDirty = true;
                interruptOccurred = false;
				break;
            case 0xE000:
                switch (kk) {
                    case 0x9E:
                        if (ioState.keyDown[V[x]]) {
                            PC += INSTR_SIZE;
                        }
                        break;
                    case 0xA1:
                        if (!ioState.keyDown[V[x]]) {
                            PC += INSTR_SIZE;
                        }
                        break;
                    default:
                }
                break;
            case 0xF000:
                switch (kk) {
                    case 0x07:
                        V[x] = DT;
                        break;
                    case 0x0A:
                        auto keyInd = ioState.keyDown[].countUntil(2);
                        if (keyInd != -1) {
                            V[x] = cast(ubyte) keyInd;
                        } else {
                            // Force execution to stop until a key is pressed.
                            // (PC doesn't move.)
                            return;
                        }
                        break;
                    case 0x15:
                        DT = V[x];
                        break;
                    case 0x18:
                        ioState.ST = V[x];
                        break;
                    case 0x1E:
                        I += V[x];
                        break;
                    case 0x29:
                        I = V[x] * 5;
                        break;
                    case 0x33:
                        ubyte val = V[x];
                        foreach_reverse (i; 0 .. 3) {
                            memory[I + i] = val % 10;
                            val /= 10;
                        }
                        break;
                    case 0x55:
                        memory[I .. I + (x + 1) * ubyte.sizeof] = V[0 .. x + 1];
                        if (ioState.useLegacyIncrement_I) I += x + 1;
                        break;
                    case 0x65:
                        V[0 .. x + 1] = memory[I .. I + (x + 1)];
                        if (ioState.useLegacyIncrement_I) I += x + 1;
                        break;
                    default:
                }
                break;
			default:
				throw new Exception("The");
		}
		// Reset released keys.
		foreach (ref key; ioState.keyDown) {
			if (key == 2) key = 0;
		}
		PC += INSTR_SIZE;
	}
}

// TODO: put inside chip8 struct 
// Load ROM program and load into memory, starting at 0x200.
void loadROM(ref Chip8 chip, string path) {
	if (path.exists && path.isFile) { // TODO: better condition?
		const(ubyte)[] prog = cast(const(ubyte)[]) read(path);

		if (ROM_MEMORY_BEGIN + prog.length > MEMORY_END) {
			throw new Exception("Program exceeds memory limit.
			File size: " ~ to!string(prog.length) ~ "B.
			Limit: " ~ to!string(MEMORY_END - ROM_MEMORY_BEGIN) ~ "B.");
		}
		
		chip.memory[ROM_MEMORY_BEGIN .. ROM_MEMORY_BEGIN + prog.length] = prog;
	} else {
		throw new Exception("A valid program file does not exist at the path: " ~ path);
	}
}
