#!/usr/bin/env python3
"""
Example Python application for Raspberry Pi
Author: Joshua D. Boyd

This application runs in a uv-managed virtual environment
"""

import time
import logging
import signal
import sys
import os
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/app/app.log'),
        logging.StreamHandler(sys.stdout)
    ]
)

logger = logging.getLogger(__name__)

class App:
    def __init__(self):
        self.running = True
        self.counter = 0

    def signal_handler(self, signum, frame):
        logger.info(f"Received signal {signum}, shutting down gracefully...")
        self.running = False

    def log_environment_info(self):
        """Log information about the Python environment"""
        logger.info(f"Python executable: {sys.executable}")
        logger.info(f"Python version: {sys.version}")
        logger.info(f"Virtual environment: {os.environ.get('VIRTUAL_ENV', 'Not set')}")
        logger.info(f"Working directory: {os.getcwd()}")

    def run(self):
        # Set up signal handlers for graceful shutdown
        signal.signal(signal.SIGTERM, self.signal_handler)
        signal.signal(signal.SIGINT, self.signal_handler)

        logger.info("Starting App service...")

        # Log environment information
        self.log_environment_info()

        try:
            while self.running:
                # Your application logic here
                self.counter += 1
                current_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                logger.info(f"Application running - Counter: {self.counter}, Time: {current_time}")

                # Example: Add your sensor reading, data processing, etc. here
                # self.read_sensors()
                # self.process_data()
                # self.send_telemetry()

                # Sleep for 60 seconds (adjust as needed)
                time.sleep(60)

        except KeyboardInterrupt:
            logger.info("Received keyboard interrupt")
        except Exception as e:
            logger.error(f"Unexpected error: {e}", exc_info=True)
        finally:
            logger.info("App service stopped")

if __name__ == "__main__":
    app = App()
    app.run()
