from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from hashlib import sha256
from secrets import randbelow, token_hex
from typing import Callable


SUPPORTED_CHANNELS = {"email", "phone"}
SUPPORTED_PURPOSES = {"password_recovery", "security_upgrade", "pec_certification"}


@dataclass(frozen=True)
class OtpChallenge:
    challenge_id: str
    destination: str
    channel: str
    purpose: str
    expires_at: datetime


@dataclass
class _StoredChallenge:
    challenge: OtpChallenge
    otp_hash: str
    consumed: bool = False


class TwoFactorService:
    """2FA foundation service with OTP over email/phone for recovery/security flows."""

    def __init__(
        self,
        *,
        otp_ttl_seconds: int = 300,
        now_provider: Callable[[], datetime] | None = None,
        email_sender: Callable[[str, str], None] | None = None,
        phone_sender: Callable[[str, str], None] | None = None,
    ) -> None:
        self._otp_ttl = otp_ttl_seconds
        self._now_provider = now_provider or (lambda: datetime.now(timezone.utc))
        self._email_sender = email_sender or (lambda destination, message: None)
        self._phone_sender = phone_sender or (lambda destination, message: None)
        self._challenges: dict[str, _StoredChallenge] = {}

    def create_challenge(self, *, destination: str, channel: str, purpose: str) -> tuple[OtpChallenge, str]:
        normalized_channel = channel.strip().lower()
        normalized_purpose = purpose.strip().lower()
        if normalized_channel not in SUPPORTED_CHANNELS:
            raise ValueError("Canale non supportato")
        if normalized_purpose not in SUPPORTED_PURPOSES:
            raise ValueError("Finalità OTP non supportata")
        if destination.strip() == "":
            raise ValueError("Destinazione OTP obbligatoria")

        otp_code = f"{randbelow(1_000_000):06d}"
        challenge_id = token_hex(16)
        now = self._now_provider()
        challenge = OtpChallenge(
            challenge_id=challenge_id,
            destination=destination.strip(),
            channel=normalized_channel,
            purpose=normalized_purpose,
            expires_at=now + timedelta(seconds=self._otp_ttl),
        )

        self._challenges[challenge_id] = _StoredChallenge(
            challenge=challenge,
            otp_hash=self._hash_otp(challenge_id, otp_code),
        )
        self._dispatch_otp(challenge=challenge, otp_code=otp_code)
        return challenge, otp_code

    def verify_challenge(self, *, challenge_id: str, otp_code: str) -> bool:
        stored = self._challenges.get(challenge_id)
        if stored is None or stored.consumed:
            return False
        now = self._now_provider()
        if now > stored.challenge.expires_at:
            return False
        if stored.otp_hash != self._hash_otp(challenge_id, otp_code):
            return False
        stored.consumed = True
        return True

    def _dispatch_otp(self, *, challenge: OtpChallenge, otp_code: str) -> None:
        message = f"Codice OTP Crimson Chat: {otp_code} (scade alle {challenge.expires_at.isoformat()})"
        if challenge.channel == "email":
            self._email_sender(challenge.destination, message)
            return
        self._phone_sender(challenge.destination, message)

    @staticmethod
    def _hash_otp(challenge_id: str, otp_code: str) -> str:
        material = f"{challenge_id}:{otp_code}".encode("utf-8")
        return sha256(material).hexdigest()
