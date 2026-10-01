import chip8;
import display;

import bindbc.sdl;
import bindbc.loader;

import main : TICKS_PER_SEC;

import std.stdio;

class SdlDisplay : Display {
    auto WINDOW_WIDTH = 64 * 15;
    auto WINDOW_HEIGHT = 32 * 15;

    const uint ON_COLOUR = 0xFFFFFFFF;
    const uint OFF_COLOUR = 0x000000FF;

    static const float SQUARE_AMPLITUDE = 0.2;
    static const uint TONE_FREQ = 261;
    static const uint SAMPLE_RATE = 44100;
    const float PHASE_INCREMENT = cast(float) TONE_FREQ / SAMPLE_RATE;
    float phase = 0.0;
    enum AUDIO_BUFFER_HEADROOM_TICKS = 2;
    
    SDL_Window *window;
    SDL_Renderer *renderer;
    SDL_Texture *texture;
    SDL_AudioStream *stream;

    const ubyte[SDL_Scancode] scancodeToKeypad = [
        SDL_SCANCODE_1: 0x1,
        SDL_SCANCODE_2: 0x2,
        SDL_SCANCODE_3: 0x3,
        SDL_SCANCODE_4: 0xC,
        SDL_SCANCODE_Q: 0x4,
        SDL_SCANCODE_W: 0x5,
        SDL_SCANCODE_E: 0x6,
        SDL_SCANCODE_R: 0xD,
        SDL_SCANCODE_A: 0x7,
        SDL_SCANCODE_S: 0x8,
        SDL_SCANCODE_D: 0x9,
        SDL_SCANCODE_F: 0xE,
        SDL_SCANCODE_Z: 0xA,
        SDL_SCANCODE_X: 0x0,
        SDL_SCANCODE_C: 0xB,
        SDL_SCANCODE_V: 0xF,
    ];

    bool init() {
        LoadMsg ret = loadSDL();
        if (ret != LoadMsg.success) {
            SDL_Log("Couldn't load SDL:");
            foreach(error; bindbc.loader.errors){
                SDL_Log(error.message);
            }
            return false;
        }

        if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO)) {
		    SDL_Log("Couldn't initialize SDL: %s", SDL_GetError());
            return false;
        }
        if (!SDL_CreateWindowAndRenderer("CHIP-8 by nungus", WINDOW_WIDTH, WINDOW_HEIGHT, SDL_WINDOW_RESIZABLE, &window, &renderer)) {
            SDL_Log("Couldn't create window/renderer: %s", SDL_GetError());
            return false;
        }
        SDL_SetRenderLogicalPresentation(renderer, LOGICAL_WIDTH, LOGICAL_HEIGHT, SDL_LOGICAL_PRESENTATION_LETTERBOX);

        texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_STREAMING, LOGICAL_WIDTH, LOGICAL_HEIGHT);
        if (!texture) {
            SDL_Log("Couldn't create streaming texture: %s", SDL_GetError());
            return false;
        }
        SDL_SetTextureScaleMode(texture, SDL_SCALEMODE_NEAREST);

        SDL_AudioSpec spec;
        spec.channels = 1;
        spec.format = SDL_AUDIO_F32;
        spec.freq = SAMPLE_RATE;
        stream = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, null, null);
        if (!stream) {
            SDL_Log("Couldn't create audio stream: %s", SDL_GetError());
            return false;
        }
        SDL_ResumeAudioStreamDevice(stream);
        return true;
    }

    void exit() {
        SDL_DestroyWindow(window);
	    SDL_Quit();
    }

    private void redraw() {
        SDL_SetRenderDrawColor(renderer, 20, 20, 20, 255);
        SDL_RenderClear(renderer);
        SDL_RenderTexture(renderer, texture, null, null);
        SDL_RenderPresent(renderer);
    }

    // Unfortunately because modern GPU texture pipelines don't support
    // bit-packed pixels for textures; pixels need to be at least byte-wise.
    // So the format SDL_PIXELFORMAT_INDEX1MSB is invalid here, meaning the
    // bit-packed bitmap parameter can't be directly passed to UpdateTexture.
    void update(ref ubyte[LOGICAL_WIDTH / 8][LOGICAL_HEIGHT] bitmap) {
        // Flatten bitmap into sequence of 32-bit pixel colours.
        uint[LOGICAL_WIDTH * LOGICAL_HEIGHT] pixels;
        foreach (i; 0 .. LOGICAL_HEIGHT) {
            foreach (j; 0 .. LOGICAL_WIDTH) {
                bool one = (bitmap[i][j / 8] >> (7 - j % 8)) & 1;
                pixels[i * LOGICAL_WIDTH + j] = one ? ON_COLOUR : OFF_COLOUR;
            }
        }
        SDL_UpdateTexture(texture, null, pixels.ptr, LOGICAL_WIDTH * uint.sizeof);
        redraw();
    }

    void updateAudio(ref IOState ioState) {
        int targetQueuedBytes = AUDIO_BUFFER_HEADROOM_TICKS * (SAMPLE_RATE / TICKS_PER_SEC) * float.sizeof;
        int currentQueuedBytes = SDL_GetAudioStreamQueued(stream);
        int byteDeficit = targetQueuedBytes - currentQueuedBytes;

        if (byteDeficit <= 0) return;
        int neededSamples = cast(int) (byteDeficit / float.sizeof);

        float[] audioBuffer = new float[neededSamples];

        // Play sound when sound timer is > 0.
        if (ioState.ST > 0) {
            foreach (ref sample; audioBuffer) {
                sample = (phase < 0.5) ? SQUARE_AMPLITUDE : -SQUARE_AMPLITUDE;
                phase += PHASE_INCREMENT;
                phase %= 1.0;
            }
        } else {
            foreach (ref sample; audioBuffer) sample = 0.0;
            phase = 0.0;
        }
        SDL_PutAudioStreamData(stream, audioBuffer.ptr, byteDeficit);
    }

    void doEventPolling(ref IOState ioState) {
        SDL_Event event;

		while (SDL_PollEvent(&event)) {
            // writeln("SDL event: ", event.type);
			switch (event.type) {
                case SDL_EVENT_KEY_DOWN:
                    if (event.key.scancode in scancodeToKeypad) {
                        ioState.keyDown[scancodeToKeypad[event.key.scancode]] = 1;
                    } else if (event.key.scancode == SDL_SCANCODE_I) {
                        ioState.useLegacyIncrement_I = !ioState.useLegacyIncrement_I;
                        writeln("toggled I-increment: ", ioState.useLegacyIncrement_I, " (desired for legacy quirk: memory ON)");
                    } else if (event.key.scancode == SDL_SCANCODE_O) {
                        ioState.useLegacySetVxToVy = !ioState.useLegacySetVxToVy;
                        writeln("toggled SetVxToVy: ", ioState.useLegacySetVxToVy, " (desired for legacy quirk: shift OFF)");
                    } else if (event.key.scancode == SDL_SCANCODE_P) {
                        ioState.useLegacySpriteInterrupt = !ioState.useLegacySpriteInterrupt;
                        writeln("toggled SpriteInterrupt: ", ioState.useLegacySpriteInterrupt, " (desired for legacy quirk: Display wait ON)");
                    } else if (event.key.scancode == SDL_SCANCODE_ESCAPE) {
                        ioState.keepExecuting = false;
                    }
                    break;
                case SDL_EVENT_KEY_UP:
                    if (event.key.scancode in scancodeToKeypad) {
                        ioState.keyDown[scancodeToKeypad[event.key.scancode]] = 2;
                    }
                    break;
				case SDL_EVENT_QUIT:
					ioState.keepExecuting = false;
					break;
                case SDL_EVENT_WINDOW_RESIZED:
                    SDL_GetWindowSizeInPixels(window, &WINDOW_WIDTH, &WINDOW_HEIGHT);
                    redraw();
                    break;
				default:
					// writeln("Unidentified SDL event: ", event.type); 
			}
		}
    }
}
