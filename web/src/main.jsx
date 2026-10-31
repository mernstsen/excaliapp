import { useCallback, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  Excalidraw,
  MainMenu,
  THEME,
  getSceneVersion,
  restore,
  serializeAsJSON,
} from "@excalidraw/excalidraw";
import "@excalidraw/excalidraw/index.css";

const native = (message) =>
  window.webkit?.messageHandlers?.excaliapp?.postMessage(message);

// Everything we persist, reduced to one string. Pointer moves, selection and
// scrolling must not register as edits, or autosave would never settle.
const fingerprint = (elements, appState, files) =>
  [
    getSceneVersion(elements),
    Object.keys(files ?? {}).length,
    appState.viewBackgroundColor,
    appState.gridSize,
    appState.gridModeEnabled,
  ].join("|");

function App() {
  const [theme, setTheme] = useState(THEME.LIGHT);

  // What Swift has on disk, what a pending write will make true once it lands,
  // and whether the next onChange is just our own document swap echoing back.
  const onDisk = useRef(null);
  const inFlight = useRef(null);
  const adoptNextAsClean = useRef(true);
  const reportedDirty = useRef(false);
  const lastDirtyPost = useRef(0);

  const onChange = useCallback((elements, appState, files) => {
    const current = fingerprint(elements, appState, files);

    if (adoptNextAsClean.current) {
      adoptNextAsClean.current = false;
      onDisk.current = current;
      return;
    }

    if (current === onDisk.current) {
      // Undone back to what is on disk, so there is nothing left to save.
      if (reportedDirty.current) {
        reportedDirty.current = false;
        native({ type: "clean" });
      }
      return;
    }

    // Swift debounces, so it needs to hear about edits as they keep coming --
    // but a freehand stroke bumps the scene version on every pointer move.
    reportedDirty.current = true;
    const now = Date.now();
    if (now - lastDirtyPost.current < 250) {
      return;
    }
    lastDirtyPost.current = now;
    native({ type: "dirty" });
  }, []);

  const handleAPI = useCallback(
    (api) => {
      window.excaliApp = {
        // Swift hands us the file's bytes; we become that document.
        loadScene(json) {
          const parsed = json ? JSON.parse(json) : { elements: [], appState: {} };
          const scene = restore(parsed, null, null);

          api.resetScene();
          api.updateScene({
            elements: scene.elements,
            appState: scene.appState,
          });
          const files = Object.values(scene.files ?? {});
          if (files.length) {
            api.addFiles(files);
          }
          if (scene.elements.length) {
            api.scrollToContent(scene.elements, {
              fitToContent: true,
              animate: false,
            });
          }

          adoptNextAsClean.current = true;
          inFlight.current = null;
          reportedDirty.current = false;
          return true;
        },

        // Called when Swift decides it is time to write.
        getSceneJSON() {
          const elements = api.getSceneElements();
          const appState = api.getAppState();
          const files = api.getFiles();
          inFlight.current = fingerprint(elements, appState, files);
          return serializeAsJSON(elements, appState, files, "local");
        },

        // Only on a successful write, so a failed save stays dirty.
        markSaved() {
          if (inFlight.current === null) {
            return false;
          }
          onDisk.current = inFlight.current;
          inFlight.current = null;
          const api2 = api;
          const stillDirty =
            fingerprint(
              api2.getSceneElements(),
              api2.getAppState(),
              api2.getFiles(),
            ) !== onDisk.current;
          reportedDirty.current = stillDirty;
          return stillDirty;
        },

        setTheme(next) {
          setTheme(next === "dark" ? THEME.DARK : THEME.LIGHT);
          return true;
        },
      };

      native({ type: "ready" });
    },
    [],
  );

  return (
    <Excalidraw
      excalidrawAPI={handleAPI}
      onChange={onChange}
      theme={theme}
      langCode="en"
      autoFocus
      UIOptions={{
        canvasActions: {
          loadScene: false,
          saveToActiveFile: false,
          export: false,
          saveAsImage: true,
          toggleTheme: false,
          clearCanvas: true,
        },
      }}
    >
      <MainMenu>
        <MainMenu.DefaultItems.SearchMenu />
        <MainMenu.DefaultItems.CommandPalette />
        <MainMenu.DefaultItems.SaveAsImage />
        <MainMenu.Separator />
        <MainMenu.DefaultItems.ChangeCanvasBackground />
      </MainMenu>
    </Excalidraw>
  );
}

createRoot(document.getElementById("root")).render(<App />);
