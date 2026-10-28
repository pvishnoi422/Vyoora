"""Exercise the same identity/media guard used by the V2 backend."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'backend'))
from media_security import (AccessDenied, FirebaseIdentity, MemoryObjects,
                            PrivateGCSObjects, create_verification_app)
