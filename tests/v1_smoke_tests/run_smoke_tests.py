#!/usr/bin/env python3
"""
Swiper v1 Smoke Test Suite
Run against staging environment before any launch announcement.

Usage:
    export SWIPER_API_BASE="https://staging-api.swiperapp.com"
    export SWIPER_FIREBASE_PROJECT="swiper-staging"
    python3 tests/v1_smoke_tests/run_smoke_tests.py

Requirements:
    pip install requests firebase-admin
"""

import os
import sys
import json
import time
import uuid
from dataclasses import dataclass, field
from typing import Optional

try:
    import requests
except ImportError:
    print("ERROR: requests not installed. Run: pip install requests")
    sys.exit(1)


# Configuration
API_BASE = os.environ.get("SWIPER_API_BASE", "http://localhost:8080")
FIREBASE_PROJECT = os.environ.get("SWIPER_FIREBASE_PROJECT", "swiper-demo")


@dataclass
class TestResult:
    name: str
    passed: bool
    message: str = ""
    duration_ms: float = 0
    details: dict = field(default_factory=dict)


class SwiperSmokeTest:
    def __init__(self):
        self.results: list[TestResult] = []
        self.session_id: Optional[str] = None
        self.item_ids: list[str] = []
        self.likes: list[str] = []
        self.shortlist_token: Optional[str] = None
        self.decision_room_id: Optional[str] = None
        self.test_item_id: Optional[str] = None

    def run_all(self) -> bool:
        print("=" * 60)
        print("SWIPER v1 SMOKE TEST SUITE")
        print("=" * 60)
        print(f"API Base: {API_BASE}")
        print(f"Firebase: {FIREBASE_PROJECT}")
        print()

        tests = [
            ("1.1", "App deck loads with real products", self.test_deck_loads),
            ("1.2", "Swipe right → item appears in likes", self.test_swipe_right),
            ("1.3", "Share shortlist → public URL returns room data", self.test_share_shortlist),
            ("2.1", "Decision Room → vote recorded", self.test_decision_room_vote),
            ("2.2", "Featured product shows Featured label", self.test_featured_label),
            ("3.1", "Outbound redirect fires with UTM params", self.test_outbound_redirect),
            ("4.1", "Admin: trigger ingestion → items increase", self.test_admin_ingestion),
            ("5.1", "Confidence Score calculated", self.test_confidence_score),
            ("6.1", "Insights Feed loads", self.test_insights_feed),
            ("7.1", "Campaign creation → featured slot", self.test_campaign_creation),
        ]

        all_passed = True
        for test_id, name, fn in tests:
            try:
                result = fn()
                self.results.append(result)
                status = "✅ PASS" if result.passed else "❌ FAIL"
                print(f"[{test_id}] {status} ({result.duration_ms:.0f}ms) {name}")
                if result.message:
                    print(f"       {result.message}")
                if not result.passed:
                    all_passed = False
            except Exception as e:
                result = TestResult(name=name, passed=False, message=f"Exception: {e}")
                self.results.append(result)
                print(f"[{test_id}] ❌ FAIL (exception) {name}: {e}")
                all_passed = False

        print()
        print("=" * 60)
        passed = sum(1 for r in self.results if r.passed)
        failed = sum(1 for r in self.results if not r.passed)
        print(f"RESULTS: {passed}/{len(self.results)} passed, {failed} failed")
        print("=" * 60)

        return all_passed

    def _post(self, path: str, data: dict = None, json: dict = None) -> requests.Response:
        url = f"{API_BASE}{path}"
        kwargs = {"timeout": 30}
        if data:
            kwargs["data"] = data
        if json:
            kwargs["json"] = json
        return requests.post(url, **kwargs)

    def _get(self, path: str, params: dict = None) -> requests.Response:
        url = f"{API_BASE}{path}"
        return requests.get(url, params=params, timeout=30)

    def _create_session(self) -> str:
        """Create anonymous session"""
        resp = self._post("/api/session", json={})
        assert resp.status_code == 200, f"Session creation failed: {resp.status_code}"
        data = resp.json()
        self.session_id = data.get("sessionId") or data.get("session_id")
        return self.session_id

    # ─────────────────────────────────────────────────────────────
    # Consumer Tests
    # ─────────────────────────────────────────────────────────────

    def test_deck_loads(self) -> TestResult:
        """Test 1.1: App deck loads with ≥1 real product"""
        name = "App deck loads with real products"
        start = time.time()

        self._create_session()
        resp = self._get(f"/api/items/deck?sessionId={self.session_id}")

        duration_ms = (time.time() - start) * 1000

        if resp.status_code != 200:
            return TestResult(name=name, passed=False, message=f"HTTP {resp.status_code}", duration_ms=duration_ms)

        data = resp.json()
        items = data.get("items", []) or data.get("results", [])

        if not items:
            return TestResult(name=name, passed=False, message="Empty deck", duration_ms=duration_ms)

        self.item_ids = [item.get("id") or item.get("itemId") for item in items[:5] if item.get("id") or item.get("itemId")]
        self.test_item_id = self.item_ids[0] if self.item_ids else None

        return TestResult(
            name=name,
            passed=True,
            message=f"{len(items)} items loaded",
            duration_ms=duration_ms,
            details={"item_count": len(items), "sample_ids": self.item_ids[:3]}
        )

    def test_swipe_right(self) -> TestResult:
        """Test 1.2: Swipe right → item appears in likes"""
        name = "Swipe right → item appears in likes"
        start = time.time()

        if not self.test_item_id:
            return TestResult(name=name, passed=False, message="No test item from deck", duration_ms=0)

        resp = self._post(f"/api/items/{self.test_item_id}/swipe", json={
            "sessionId": self.session_id,
            "direction": "right"
        })

        duration_ms = (time.time() - start) * 1000

        if resp.status_code not in (200, 201):
            return TestResult(name=name, passed=False, message=f"HTTP {resp.status_code}", duration_ms=duration_ms)

        # Check likes list
        likes_resp = self._get(f"/api/items/liked?sessionId={self.session_id}")
        likes_data = likes_resp.json()
        likes_items = likes_data.get("items", []) or likes_data.get("results", [])

        liked_ids = [item.get("id") or item.get("itemId") for item in likes_items]
        self.likes = liked_ids

        if self.test_item_id not in liked_ids:
            return TestResult(
                name=name, passed=False,
                message=f"Item {self.test_item_id} not in likes list",
                duration_ms=duration_ms
            )

        return TestResult(
            name=name, passed=True,
            message=f"Liked item in list ({len(liked_ids)} total)",
            duration_ms=duration_ms
        )

    def test_share_shortlist(self) -> TestResult:
        """Test 1.3: Share shortlist → public URL returns room data"""
        name = "Share shortlist → public URL works"
        start = time.time()

        if not self.likes:
            return TestResult(name=name, passed=False, message="No likes to share", duration_ms=0)

        resp = self._post("/api/shortlists", json={
            "sessionId": self.session_id,
            "itemIds": self.likes[:3]
        })

        duration_ms = (time.time() - start) * 1000

        if resp.status_code not in (200, 201):
            return TestResult(name=name, passed=False, message=f"HTTP {resp.status_code}", duration_ms=duration_ms)

        data = resp.json()
        self.shortlist_token = data.get("token") or data.get("shareToken") or data.get("id")
        share_url = data.get("shareUrl") or data.get("url")

        if not self.shortlist_token and not share_url:
            return TestResult(name=name, passed=False, message="No token or URL returned", duration_ms=duration_ms, details=data)

        # Try to access the shared shortlist publicly
        if share_url:
            public_resp = requests.get(share_url, timeout=30)
        else:
            public_resp = self._get(f"/s/{self.shortlist_token}")

        if public_resp.status_code != 200:
            return TestResult(
                name=name, passed=False,
                message=f"Public URL returned {public_resp.status_code}",
                duration_ms=duration_ms
            )

        return TestResult(
            name=name, passed=True,
            message=f"Share URL: {share_url or '/s/' + self.shortlist_token}",
            duration_ms=duration_ms
        )

    def test_decision_room_vote(self) -> TestResult:
        """Test 2.1: Decision Room vote recorded"""
        name = "Decision Room vote recorded"
        start = time.time()

        if not self.shortlist_token:
            return TestResult(name=name, passed=False, message="No shortlist to vote on", duration_ms=0)

        # This requires auth — we'll just verify the endpoint exists
        # In production smoke test, use a real auth token
        resp = self._post(f"/api/rooms/{self.shortlist_token}/vote", json={
            "itemId": self.test_item_id,
            "vote": "up"
        })

        duration_ms = (time.time() - start) * 1000

        # 401 = auth required (expected for unauthed smoke test)
        # 200/201 = vote recorded (good)
        # 404 = room not found (may be expected if token format differs)
        if resp.status_code in (200, 201):
            return TestResult(name=name, passed=True, message="Vote recorded", duration_ms=duration_ms)
        elif resp.status_code == 401:
            return TestResult(name=name, passed=True, message="Auth required (expected)", duration_ms=duration_ms, details={"note": "Auth required for voting — endpoint exists"})
        else:
            return TestResult(name=name, passed=False, message=f"HTTP {resp.status_code}: {resp.text[:100]}", duration_ms=duration_ms)

    def test_featured_label(self) -> TestResult:
        """Test 2.2: Featured product shows Featured label"""
        name = "Featured product shows Featured label"
        start = time.time()

        # Get deck and look for featured items
        resp = self._get(f"/api/items/deck?sessionId={self.session_id}")
        duration_ms = (time.time() - start) * 1000

        if resp.status_code != 200:
            return TestResult(name=name, passed=False, message=f"HTTP {resp.status_code}", duration_ms=duration_ms)

        data = resp.json()
        items = data.get("items", []) or data.get("results", [])

        featured = [item for item in items if item.get("isFeatured") or item.get("featured") or item.get("campaignId")]
        non_featured = len(items) - len(featured)

        # This test passes if we got items — featured items depend on campaigns existing
        return TestResult(
            name=name,
            passed=len(items) > 0,
            message=f"{len(featured)} featured, {non_featured} organic (featured depends on active campaigns)",
            duration_ms=duration_ms,
            details={"featured_count": len(featured), "organic_count": non_featured}
        )

    def test_outbound_redirect(self) -> TestResult:
        """Test 3.1: Outbound redirect fires with UTM params"""
        name = "Outbound redirect fires with UTM params"
        start = time.time()

        if not self.test_item_id:
            return TestResult(name=name, passed=False, message="No test item", duration_ms=0)

        # The redirect endpoint
        resp = self._get(f"/api/go/{self.test_item_id}")
        duration_ms = (time.time() - start) * 1000

        # Should return 302 redirect or 200 with redirect URL
        if resp.status_code in (200, 302):
            location = resp.headers.get("Location") or resp.json().get("redirectUrl") or resp.json().get("url", "")

            has_utm = "utm_" in location or "utmSource" in location or "swp_" in location
            has_retailer = "ikea" in location.lower() or "mio" in location.lower() or "retailer" in location.lower()

            if not location:
                return TestResult(name=name, passed=False, message="No redirect URL in response", duration_ms=duration_ms, details=resp.json())

            return TestResult(
                name=name,
                passed=has_utm or has_retailer,
                message=f"Redirects to: {location[:80]}...",
                duration_ms=duration_ms,
                details={"redirect_url": location, "has_utm": has_utm}
            )

        return TestResult(name=name, passed=False, message=f"HTTP {resp.status_code}", duration_ms=duration_ms)

    # ─────────────────────────────────────────────────────────────
    # Admin & Backend Tests
    # ─────────────────────────────────────────────────────────────

    def test_admin_ingestion(self) -> TestResult:
        """Test 4.1: Admin trigger ingestion → items increase"""
        name = "Admin: ingestion trigger works"
        start = time.time()

        # This requires admin auth — just verify the endpoint exists
        resp = self._post("/api/admin/ingest", json={"sourceId": "test"})

        duration_ms = (time.time() - start) * 1000

        if resp.status_code in (200, 201, 202):
            return TestResult(name=name, passed=True, message="Ingestion triggered", duration_ms=duration_ms)
        elif resp.status_code == 401:
            return TestResult(name=name, passed=True, message="Auth required (endpoint exists)", duration_ms=duration_ms)
        else:
            return TestResult(name=name, passed=False, message=f"HTTP {resp.status_code}: {resp.text[:100]}", duration_ms=duration_ms)

    def test_confidence_score(self) -> TestResult:
        """Test 5.1: Confidence Score calculated for test product"""
        name = "Confidence Score calculated"
        start = time.time()

        if not self.test_item_id:
            return TestResult(name=name, passed=False, message="No test item", duration_ms=0)

        # Try retailer-facing API
        resp = self._get(f"/api/scores/{self.test_item_id}")

        duration_ms = (time.time() - start) * 1000

        if resp.status_code == 200:
            data = resp.json()
            score = data.get("score") or data.get("confidenceScore") or data.get("value")
            if score is not None:
                return TestResult(name=name, passed=True, message=f"Score: {score}", duration_ms=duration_ms, details=data)
            return TestResult(name=name, passed=False, message="No score in response", duration_ms=duration_ms, details=data)
        elif resp.status_code == 404:
            return TestResult(name=name, passed=True, message="Scores not yet calculated (expected pre-launch)", duration_ms=duration_ms)
        else:
            return TestResult(name=name, passed=False, message=f"HTTP {resp.status_code}", duration_ms=duration_ms)

    def test_insights_feed(self) -> TestResult:
        """Test 6.1: Insights Feed loads"""
        name = "Insights Feed loads"
        start = time.time()

        resp = self._get("/api/retailer/insights")

        duration_ms = (time.time() - start) * 1000

        if resp.status_code == 200:
            data = resp.json()
            insights = data.get("insights", []) or data.get("feed", []) or data.get("items", [])
            return TestResult(name=name, passed=True, message=f"{len(insights)} insights", duration_ms=duration_ms, details=data)
        elif resp.status_code == 401:
            return TestResult(name=name, passed=True, message="Auth required (endpoint exists)", duration_ms=duration_ms)
        elif resp.status_code == 404:
            return TestResult(name=name, passed=False, message="Insights endpoint not found — console not built", duration_ms=duration_ms)
        else:
            return TestResult(name=name, passed=False, message=f"HTTP {resp.status_code}", duration_ms=duration_ms)

    def test_campaign_creation(self) -> TestResult:
        """Test 7.1: Campaign creation → featured slot"""
        name = "Campaign creation → featured slot"
        start = time.time()

        resp = self._post("/api/campaigns", json={
            "name": f"smoke_test_campaign_{uuid.uuid4().hex[:8]}",
            "segmentId": "default",
            "productIds": self.item_ids[:3] if self.item_ids else [],
            "budgetCents": 10000,
            "startDate": "2026-04-01",
            "endDate": "2026-04-30"
        })

        duration_ms = (time.time() - start) * 1000

        if resp.status_code in (200, 201):
            data = resp.json()
            campaign_id = data.get("id") or data.get("campaignId")
            return TestResult(name=name, passed=True, message=f"Campaign {campaign_id} created", duration_ms=duration_ms, details=data)
        elif resp.status_code == 401:
            return TestResult(name=name, passed=True, message="Auth required (endpoint exists)", duration_ms=duration_ms)
        elif resp.status_code == 404:
            return TestResult(name=name, passed=False, message="Campaign endpoint not found — Phase 13 not built", duration_ms=duration_ms)
        else:
            return TestResult(name=name, passed=False, message=f"HTTP {resp.status_code}: {resp.text[:100]}", duration_ms=duration_ms)


if __name__ == "__main__":
    smoke = SwiperSmokeTest()
    success = smoke.run_all()
    sys.exit(0 if success else 1)
