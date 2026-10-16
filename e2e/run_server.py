"""Run the Flow backend against the local throwaway PostgreSQL with all externals stubbed."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402  (must come first)

os.chdir(stubenv.BACKEND)
import main  # noqa: E402

stubenv.patch_loaded_modules()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(main.app, host="127.0.0.1", port=int(os.environ.get("E2E_PORT", "8765")), log_level="warning")
