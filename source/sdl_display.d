import chip8;
import display;

import bindbc.sdl;
import bindbc.loader;

class SdlDisplay : Display {
    const auto DISPLAY_WIDTH = 64 * 5;
    const auto DISPLAY_HEIGHT = 32 * 5;
    
    SDL_Window *window;

    void doEventPolling(ref IOState ioState) {
        SDL_Event event;

		while (SDL_PollEvent(&event)) {
			switch (event.type) {
				case SDL_EVENT_QUIT:
					ioState.keepExecuting = false;
					break;
				default:
					// writeln("Unidentified SDL event: ", event.type); 
			}
		}
    }

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

        window = SDL_CreateWindow("CHIP-8", DISPLAY_WIDTH, DISPLAY_HEIGHT, 0);
        if (window == null) {
            SDL_Log("Couldn't create window: %s", SDL_GetError());
            return false;
        }

        return true;
    }

    void exit() {
        SDL_DestroyWindow(window);
	    SDL_Quit();
    }

    void update(ubyte[8][32] bitmap) {}
}
