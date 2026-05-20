from __future__ import annotations

import unittest
from datetime import datetime, timedelta, timezone

from otp_2fa import TwoFactorService


class TwoFactorServiceTest(unittest.TestCase):
    def test_email_challenge_is_generated_sent_and_verified_once(self) -> None:
        sent_messages: list[tuple[str, str]] = []
        service = TwoFactorService(
            email_sender=lambda destination, message: sent_messages.append((destination, message))
        )

        challenge, otp = service.create_challenge(
            destination="user@example.com",
            channel="email",
            purpose="password_recovery",
        )

        self.assertEqual("email", challenge.channel)
        self.assertEqual("user@example.com", sent_messages[0][0])
        self.assertTrue(service.verify_challenge(challenge_id=challenge.challenge_id, otp_code=otp))
        self.assertFalse(service.verify_challenge(challenge_id=challenge.challenge_id, otp_code=otp))

    def test_phone_challenge_fails_after_expiry(self) -> None:
        now = datetime(2026, 1, 1, tzinfo=timezone.utc)
        mutable_now = {"value": now}
        service = TwoFactorService(
            otp_ttl_seconds=30,
            now_provider=lambda: mutable_now["value"],
            phone_sender=lambda destination, message: None,
        )

        challenge, otp = service.create_challenge(
            destination="+39000000000",
            channel="phone",
            purpose="security_upgrade",
        )
        mutable_now["value"] = now + timedelta(seconds=31)
        self.assertFalse(service.verify_challenge(challenge_id=challenge.challenge_id, otp_code=otp))

    def test_invalid_channel_is_rejected(self) -> None:
        service = TwoFactorService()
        with self.assertRaises(ValueError):
            service.create_challenge(
                destination="user@example.com",
                channel="push",
                purpose="password_recovery",
            )


if __name__ == "__main__":
    unittest.main()
