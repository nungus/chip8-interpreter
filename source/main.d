import std.stdio;
import std.file;
import std.conv : to;


// Ideas:
// - ASCII graphics? `SPACE` for 1, `#` for 0.

struct Chip8 {
	ubyte[4096] memory; // 0x000 -> 0x1FF: Location of original interpreter.
	ubyte[16] V; // Registers.
	ushort I;
	ubyte delayReg;
	ubyte soundReg;
	ushort PC;
	ubyte SP;
	ushort[16] stack;
}

const int ROM_MEMORY_BEGIN = 0x200;
const int MEMORY_END = 0xFFF;


// Load ROM program and load into memory, starting at 0x200.
void loadROM(ref Chip8 chip, string path) {
	if (path.exists && path.isFile) { // TODO: better condition?
		const(ubyte)[] prog = cast(const(ubyte)[]) read(path);

		if (ROM_MEMORY_BEGIN + prog.length > MEMORY_END) {
			throw new Exception("Program exceeds memory limit.
			File size: " ~ to!string(prog.length) ~ "B.
			Limit: " ~ to!string(MEMORY_END - ROM_MEMORY_BEGIN) ~ "B.");
		}
		
		chip.memory[ROM_MEMORY_BEGIN..ROM_MEMORY_BEGIN + prog.length] = prog;
	} else {
		throw new Exception("A valid program file does not exist at the path: " ~ path);
	}
}


void main(string[] args)
{
	Chip8 chip;
	writeln("HELLO YELLO!");
	// writeln("Entry 0x200 is ", chip.memory[0x200]);
	loadROM(chip, args[1]);
	writeln("Loaded program.");
	// writeln("Entry 0x200 is ", chip.memory[0x200]);
}
