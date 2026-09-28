import chip8;
import display;

import bindbc.sdl;
import bindbc.loader;

import std.stdio;

class SdlDisplay : Display {
    const auto WINDOW_WIDTH = 640;
    const auto WINDOW_HEIGHT = 320;

    const uint ON_COLOUR = 0xFFFFFFFF;
    const uint OFF_COLOUR = 0x00000000;
    
    SDL_Window *window;
    SDL_Renderer *renderer;
    SDL_Texture *texture;

    bool init() {
        LoadMsg ret = loadSDL();
        if (ret != LoadMsg.success) {
            SDL_Log("Couldn't load SDL:");
            foreach(error; bindbc.loader.errors){
                SDL_Log(error.message);
            }
            return false;
        }

        if (!SDL_Init(SDL_INIT_VIDEO)) {
		    SDL_Log("Couldn't initialize SDL: %s", SDL_GetError());
            return false;
        }
        if (!SDL_CreateWindowAndRenderer("CHIP-8", WINDOW_WIDTH, WINDOW_HEIGHT, SDL_WINDOW_RESIZABLE, &window, &renderer)) {
            SDL_Log("Couldn't create window/renderer: %s", SDL_GetError());
            return false;
        }
        SDL_SetRenderLogicalPresentation(renderer, LOGICAL_WIDTH, LOGICAL_HEIGHT, SDL_LOGICAL_PRESENTATION_LETTERBOX);

        texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_STREAMING, LOGICAL_WIDTH, LOGICAL_HEIGHT);
        if (!texture) {
            SDL_Log("Couldn't create streaming texture: %s", SDL_GetError());
            return false;
        }
        return true;
    }

    void exit() {
        SDL_DestroyWindow(window);
	    SDL_Quit();
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
        SDL_RenderClear(renderer);
        SDL_RenderTexture(renderer, texture, null, null);
        SDL_RenderPresent(renderer);
    }

    void doEventPolling(ref IOState ioState) {
        SDL_Event event;

		while (SDL_PollEvent(&event)) {
            writeln("SDL event: ", event.type);
			switch (event.type) {
				case SDL_EVENT_QUIT:
					ioState.keepExecuting = false;
					break;
				default:
					// writeln("Unidentified SDL event: ", event.type); 
			}
		}
    }
    
}
