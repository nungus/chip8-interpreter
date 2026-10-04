import core.time;
import core.thread;
import std.stdio;

import chip8;
import display;

const int INSTRS_PER_SEC = 720;
const int TICKS_PER_SEC = 60;

int main(string[] args) {
	const int instrsPerTick = INSTRS_PER_SEC / 60;
	const Duration msPerTick = (1000 / TICKS_PER_SEC).msecs;
	// writeln("instrsPerTick: ", instrsPerTick);
	// writeln("msPerTick: ", msPerTick);

	Chip8 chip = Chip8.create();
	auto chippy = "CHIPPY-8 > HELLO YELLO!";
	chippy = "CHIPPY-8 > MY... OCTONARY CEPHALOFORME.";
	loadROM(chip, args[1]);
	writeln("Loaded program.");

	import sdl_display;
	Display display = new SdlDisplay();
	if (!display.init()) {
		writeln("Terminated due to display init fail.");
		return 1;
	}
	writeln("Initialised display.");

	auto executeBeginTime = MonoTime.currTime;
	bool secondTrigger;
	long secondsElapsed = 0;
	int numTicksInSecond = 0;
	while (chip.ioState.keepExecuting) {
		auto tickBeginTime = MonoTime.currTime;

		display.doEventPolling(chip.ioState);
		foreach (t; 0 .. instrsPerTick) {
			chip.executeInstruction();
		}
		if (chip.ioState.displayDirty) {
			// writeln("Redrawing framebuffer.");
			display.update(chip.fb.bitmap);
			chip.ioState.displayDirty = false;
		}
		
		display.updateAudio(chip.ioState);
		if (chip.DT > 0) chip.DT--;
		if (chip.ioState.ST > 0) chip.ioState.ST--;
		chip.interruptOccurred = true;
		
		auto tickElapsedTime = MonoTime.currTime - tickBeginTime;
		if (tickElapsedTime < msPerTick) {
			Thread.sleep(msPerTick - tickElapsedTime);
			// Thread.sleep(1.msecs);
			// writeln("Slept for ", msPerTick - tickElapsedTime);
		}
		numTicksInSecond++;
		if ((MonoTime.currTime - executeBeginTime) % 1.seconds < 500.msecs) {
			if (!secondTrigger) {
				writeln(i"[$(secondsElapsed)] Live TPS: $(numTicksInSecond).");
				numTicksInSecond = 0;
				secondTrigger = true;
				secondsElapsed++;
			}
		} else {
			secondTrigger = false;
		}
	}
	display.exit();
	chippy = "CHIPPY-8 > A MISTRANSLATION... I WAS ALMOST THERE. WAIT ";
	writeln("Program closed.");
	return 0;
}
