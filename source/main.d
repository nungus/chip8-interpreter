import core.time;
import core.thread;
import std.stdio;

import chip8;
import display;

const int INSTRS_PER_TICK = 10;

int main(string[] args) {
	Chip8 chip = Chip8.create();
	writeln("HELLO YELLO! I'm CHIPPY-8! >:D");
	loadROM(chip, args[1]);
	writeln("Loaded program.");

	import sdl_display;
	Display display = new SdlDisplay();
	if (!display.init()) {
		writeln("Terminated due to display init fail.");
		return 1;
	}
	writeln("Initialised display.");

	while (chip.ioState.keepExecuting) {
		// TODO: Time execution, choose appropriate target num. instrs / sec.
		display.doEventPolling(chip.ioState);
		foreach (t; 0 .. INSTRS_PER_TICK) {
			chip.executeInstruction();
		}
		if (chip.ioState.displayDirty) {
			// writeln("Redrawing framebuffer.");
			display.update(chip.fb.bitmap);
			chip.ioState.displayDirty = false;
		}
		chip.DT--;
		chip.ST--;
		chip.interruptOccurred = true;
		Thread.sleep(1.msecs);
	}
	display.exit();
	writeln("Program closed.");
	return 0;
}
