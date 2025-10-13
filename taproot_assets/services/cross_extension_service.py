"""Service for cross-extension communication."""
from datetime import datetime, timezone
from typing import Dict, Any, Optional
from lnbits.core.models import Payment
from lnbits.tasks import invoice_listeners
from loguru import logger


class CrossExtensionService:
    """Handle communication between Taproot Assets and other extensions."""
    
    @staticmethod
    async def emit_taproot_payment_event(
        payment_hash: str,
        asset_id: str,
        asset_amount: int,
        satoshi_amount: int,
        extra: Optional[Dict[str, Any]] = None,
        wallet_id: Optional[str] = None
    ):
        """
        Emit a payment event that other extensions can listen to.
        This mimics the LNbits core payment event structure.
        """
        # Create a Payment-like object for compatibility
        payment_event = Payment(
            checking_id=payment_hash,  # Use payment_hash as checking_id for taproot payments
            payment_hash=payment_hash,
            bolt11="",  # Not used for taproot payments
            amount=satoshi_amount,  # Use satoshi amount for compatibility
            memo=extra.get("description", "") if extra else "",
            time=datetime.now(timezone.utc),
            fee=0,
            preimage="",
            status="success",  # Set status to success for completed payments
            extra=extra or {},
            wallet_id=wallet_id or "",
            webhook=None,
            webhook_status=None
        )
        
        # Add taproot-specific fields to extra
        payment_event.extra.update({
            "is_taproot": True,
            "asset_id": asset_id,
            "asset_amount": asset_amount,
        })
        
        # Preserve original extra data
        if extra:
            for key, value in extra.items():
                if key not in ["is_taproot", "asset_id", "asset_amount"]:
                    payment_event.extra[key] = value
        
        # Notify all registered listeners except taproot's own
        for name, queue in invoice_listeners.items():
            if "taproot" not in name.lower():  # Don't notify taproot's own listener
                try:
                    await queue.put(payment_event)
                    logger.info(f"Notified {name} about taproot payment {payment_hash}")
                except Exception as e:
                    logger.error(f"Failed to notify {name} about payment: {e}")