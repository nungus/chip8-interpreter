import core.time;
import core.thread;
import std.stdio;

import chip8;
import display;


int main(string[] args) {
	Chip8 chip;
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
		chip.executeInstruction();
		if (chip.ioState.displayDirty) {
			display.update(chip.fb.bitmap);
			chip.ioState.displayDirty = false;
		}
		Thread.sleep(1.msecs);
	}
	display.exit();
	writeln("Program closed.");
	return 0;
}
