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
		ubyte xByteLeft = (x % (8 * BITMAP_W_BYTES)) / 8;
		ubyte xByteRight = cast(ubyte) (xByteLeft + 1) % BITMAP_W_BYTES;
		ubyte xByteOffset = x % 8;
		bool causedPixelErasure = 0;
		for (int i = 0; i < sprBytes.length; i++) {
			auto y_i = (y + i) % BITMAP_H_PX;

			// Left
			ubyte sprByteLeft = sprBytes[i] >> xByteOffset;
			causedPixelErasure |= (bitmap[y_i][xByteLeft] & sprByteLeft) != 0;
			bitmap[y_i][xByteLeft] ^= sprByteLeft;

			// Right
			ubyte sprByteRight = cast(ubyte) (sprBytes[i] << (8 - xByteOffset));
			causedPixelErasure |= (bitmap[y_i][xByteRight] & sprByteRight) != 0;
			bitmap[y_i][xByteRight] ^= sprByteRight;
		}
		return causedPixelErasure;
	}
}

struct IOState {
	bool keepExecuting = true;
    bool displayDirty = false; // Set when bitmap is modified with Dxyn. Purpose is to signal a display update. NOT cleared by the CHIP-8.
	ubyte[16] keyDown; // 1 when down, 0 when up.
}

struct Chip8 {
	ubyte[4096] memory; // 0x000 -> 0x1FF: Location of original interpreter.
	ubyte[16] V; // Registers.
	ushort I;
	ubyte delayReg;
	ubyte soundReg;
	ushort PC = ROM_MEMORY_BEGIN;
	byte SP = -1;
	ushort[16] stack;
    ubyte DT; // Delay timer.
    ubyte ST; // Sound timer.

	Framebuffer fb;
	IOState ioState;

	auto rnd = Random();

	void stackPush(ushort value) {
		stack[++SP] = value;
	}
	ushort stackPop() {
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
				PC = nnn; // TODO: Could rearrange to do fall-through for the above case, not going to rn.
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
						break;
					case 2:
						V[x] &= V[y];
						break;
					case 3:
						V[x] ^= V[y];
						break;
					case 4:
						auto sum = V[x] + V[y];
						V[0xF] = sum > 255;
						V[x] = cast(ubyte) sum;
						break;
					case 5:
						V[0xF] = V[x] > V[y];
						V[x] -= V[y];
						break;
					case 6:
						V[0xF] = V[x] & 1;
						V[x] >>= 1;
						break;
					case 7:
						V[0xF] = V[y] > V[x];
						V[x] = cast(ubyte) (V[y] - V[x]);
						break;
					case 0xE:
						V[0xF] = (V[x] >> 7) & 1;
						V[x] <<= 1;
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
				break;
			case 0xC000:
				V[x] = kk & uniform(0, 256, rnd);
				break;
			case 0xD000:
				V[0xF] = fb.drawSprite(memory[I .. I + n], V[x], V[y]);
                ioState.displayDirty = true;
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
                        ubyte keyInd = cast(ubyte) ioState.keyDown[].countUntil(1);
                        if (keyInd != -1) {
                            V[x] = keyInd;
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
                        ST = V[x];
                        break;
                    case 0x1E:
                        I += V[x];
                        break;
                    default:
                }
                break;
			default:
				throw new Exception("The");
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
