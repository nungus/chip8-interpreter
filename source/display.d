module display;
import chip8;
import std.file;

// The display is responsible for:
// - outputting the bitmap to the screen,
// - logging keyboard events.
interface Display {
    bool init();
    void exit();
    void update(ref ubyte[8][32] bitmap); // TODO: just put bitmap in IOState tbh? that's more consistent... OK maybe not actually since now i handle audio separately
    void updateAudio(ref IOState ioState);
    void doEventPolling(ref IOState ioState);
}
