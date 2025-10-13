import os
from typing import Dict, Any, Optional
from loguru import logger
from pathlib import Path

# Default cache expiry times
ASSET_CACHE_EXPIRY_SECONDS = 300  # 5 minutes

class TaprootSettings:
    """
    Load Taproot Assets settings from config file or environment variables.
    Supports both litd integrated mode (no config needed) and standalone tapd mode.
    """
    
    def __init__(self):
        # Load settings from config file
        config_values = self._load_config_file()
        
        # Check if we have any tapd-specific configuration
        self.has_standalone_config = bool(
            config_values.get("TAPD_HOST") or 
            os.environ.get("TAPD_HOST") or
            config_values.get("TAPD_TLS_CERT_PATH") or
            os.environ.get("TAPD_TLS_CERT_PATH")
        )
        
        # TAPD connection settings
        # First try config file, then environment variables
        self.tapd_host = config_values.get("TAPD_HOST") or os.environ.get("TAPD_HOST", None)
        self.tapd_network = config_values.get("TAPD_NETWORK") or os.environ.get("TAPD_NETWORK", "mainnet")
        self.tapd_tls_cert_path = config_values.get("TAPD_TLS_CERT_PATH") or os.environ.get("TAPD_TLS_CERT_PATH", None)
        self.tapd_macaroon_path = config_values.get("TAPD_MACAROON_PATH") or os.environ.get("TAPD_MACAROON_PATH", None)
        self.tapd_macaroon_hex = config_values.get("TAPD_MACAROON_HEX") or os.environ.get("TAPD_MACAROON_HEX", None)
        
        # LND connection settings
        self.lnd_macaroon_path = config_values.get("LND_REST_MACAROON") or os.environ.get("LND_REST_MACAROON", None)
        self.lnd_macaroon_hex = config_values.get("LND_MACAROON_HEX") or os.environ.get("LND_MACAROON_HEX", None)
        
        # Fee settings
        default_fee = config_values.get("TAPD_DEFAULT_SAT_FEE") or os.environ.get("TAPD_DEFAULT_SAT_FEE", "1")
        self.default_sat_fee = int(default_fee)
        
        # Only log config details if we have standalone configuration
        if self.has_standalone_config:
            logger.info("Taproot Assets settings loaded for standalone tapd mode")
            logger.info(f"TAPD_HOST: {self.tapd_host}")
            logger.info(f"TAPD_TLS_CERT_PATH: {self.tapd_tls_cert_path}")
            logger.info(f"TAPD_MACAROON_PATH: {self.tapd_macaroon_path}")
        else:
            logger.info("No standalone tapd configuration found, will attempt litd integrated mode")
    
    def _load_config_file(self) -> Dict[str, str]:
        """Load settings from taproot_assets.conf file."""
        config_values = {}
        config_path = Path(__file__).parent / "taproot_assets.conf"
        
        if config_path.exists():
            try:
                with open(config_path, 'r') as f:
                    for line in f:
                        line = line.strip()
                        # Skip comments and empty lines
                        if line and not line.startswith('#') and '=' in line:
                            key, value = line.split('=', 1)
                            key = key.strip()
                            value = value.strip()
                            # Remove quotes if present
                            if value.startswith('"') and value.endswith('"'):
                                value = value[1:-1]
                            elif value.startswith("'") and value.endswith("'"):
                                value = value[1:-1]
                            config_values[key] = value
                logger.debug(f"Loaded config from {config_path}")
            except Exception as e:
                logger.error(f"Error loading config file: {e}")
        else:
            # Don't warn about missing config file - it's optional now
            logger.debug(f"Config file not found at {config_path}, will use litd integrated mode if available")
        
        return config_values
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert settings to a dictionary for API responses."""
        return {
            "tapd_host": self.tapd_host,
            "tapd_network": self.tapd_network,
            "tapd_tls_cert_path": self.tapd_tls_cert_path,
            "tapd_macaroon_path": self.tapd_macaroon_path,
            "tapd_macaroon_hex": self.tapd_macaroon_hex,
            "lnd_macaroon_path": self.lnd_macaroon_path,
            "lnd_macaroon_hex": self.lnd_macaroon_hex,
            "default_sat_fee": self.default_sat_fee
        }

# Create a singleton instance
taproot_settings = TaprootSettings()
