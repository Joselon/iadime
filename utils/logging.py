import logging
import os
import sys
from typing import Optional

DEFAULT_LOG_FORMAT = "%(asctime)s %(levelname)s [%(name)s] %(message)s"


def configure_logger(name: str = "iadime.web", level: Optional[str] = None) -> logging.Logger:
    logger = logging.getLogger(name)
    if logger.handlers:
        return logger

    resolved_level = (level or os.getenv("IADIME_LOG_LEVEL", "INFO")).upper()
    logger.setLevel(getattr(logging, resolved_level, logging.INFO))

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter(DEFAULT_LOG_FORMAT))
    logger.addHandler(handler)
    logger.propagate = False
    return logger
