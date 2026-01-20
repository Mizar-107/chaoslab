#!/usr/bin/env python3
"""
Load Generator for MicroShop Chaos Engineering

Generates realistic HTTP traffic patterns for observing system behavior
during chaos experiments.

Usage:
    python load-generator.py --profile steady
    python load-generator.py --profile peak --url http://localhost:8080
"""

import asyncio
import aiohttp
import random
import time
import argparse
import sys
from dataclasses import dataclass
from typing import List, Dict
from datetime import datetime


@dataclass
class LoadProfile:
    """Defines a load testing profile."""
    name: str
    rps: int  # Requests per second
    duration_seconds: int
    endpoints: List[str]
    description: str


# API Endpoints to test
ENDPOINTS = {
    "home": "/",
    "catalog": "/api/catalog",
    "product": "/api/catalog/products/{id}",
    "cart": "/api/cart",
    "cart_add": "/api/cart/add",
    "checkout": "/api/checkout",
}

# Available load profiles
PROFILES = {
    "steady": LoadProfile(
        name="steady",
        rps=10,
        duration_seconds=300,
        endpoints=["home", "catalog", "product"],
        description="Low steady traffic - good for baseline"
    ),
    "shopping": LoadProfile(
        name="shopping",
        rps=25,
        duration_seconds=180,
        endpoints=["home", "catalog", "product", "cart"],
        description="Moderate shopping traffic"
    ),
    "peak": LoadProfile(
        name="peak",
        rps=50,
        duration_seconds=60,
        endpoints=list(ENDPOINTS.keys()),
        description="High peak load - all endpoints"
    ),
    "chaos": LoadProfile(
        name="chaos",
        rps=30,
        duration_seconds=600,
        endpoints=list(ENDPOINTS.keys()),
        description="Extended load for chaos experiments (10 min)"
    ),
    "spike": LoadProfile(
        name="spike",
        rps=100,
        duration_seconds=30,
        endpoints=["home", "catalog"],
        description="Short burst spike test"
    ),
}


class LoadGenerator:
    """Async HTTP load generator."""

    def __init__(self, base_url: str, profile: LoadProfile, verbose: bool = False):
        self.base_url = base_url.rstrip('/')
        self.profile = profile
        self.verbose = verbose
        self.stats: Dict[str, any] = {
            "total_requests": 0,
            "success": 0,
            "failure": 0,
            "latencies": [],
            "status_codes": {},
            "errors": [],
            "start_time": None,
            "end_time": None,
        }
        self._running = False

    def _get_endpoint_url(self, endpoint_key: str) -> str:
        """Get the full URL for an endpoint, substituting placeholders."""
        path = ENDPOINTS[endpoint_key]
        
        # Replace placeholders with random values
        if "{id}" in path:
            path = path.replace("{id}", str(random.randint(1, 100)))
        
        return f"{self.base_url}{path}"

    async def _make_request(self, session: aiohttp.ClientSession, endpoint_key: str):
        """Make a single HTTP request and record metrics."""
        url = self._get_endpoint_url(endpoint_key)
        start_time = time.time()
        
        try:
            async with session.get(
                url,
                timeout=aiohttp.ClientTimeout(total=5)
            ) as response:
                await response.text()  # Consume response
                latency_ms = (time.time() - start_time) * 1000
                
                self.stats["latencies"].append(latency_ms)
                self.stats["total_requests"] += 1
                
                # Track status codes
                status = response.status
                self.stats["status_codes"][status] = self.stats["status_codes"].get(status, 0) + 1
                
                if status < 400:
                    self.stats["success"] += 1
                else:
                    self.stats["failure"] += 1
                
                if self.verbose:
                    print(f"  [{status}] {endpoint_key}: {latency_ms:.1f}ms")
                    
        except asyncio.TimeoutError:
            self.stats["failure"] += 1
            self.stats["total_requests"] += 1
            self.stats["errors"].append(f"Timeout: {endpoint_key}")
            if self.verbose:
                print(f"  [TIMEOUT] {endpoint_key}")
                
        except aiohttp.ClientError as e:
            self.stats["failure"] += 1
            self.stats["total_requests"] += 1
            self.stats["errors"].append(f"ClientError: {str(e)[:50]}")
            if self.verbose:
                print(f"  [ERROR] {endpoint_key}: {e}")
                
        except Exception as e:
            self.stats["failure"] += 1
            self.stats["total_requests"] += 1
            self.stats["errors"].append(f"Exception: {str(e)[:50]}")

    async def run(self):
        """Run the load generator."""
        print(f"\n{'='*60}")
        print(f"🚀 Starting Load Generator")
        print(f"{'='*60}")
        print(f"   Profile:    {self.profile.name}")
        print(f"   Description: {self.profile.description}")
        print(f"   Target:     {self.base_url}")
        print(f"   RPS:        {self.profile.rps}")
        print(f"   Duration:   {self.profile.duration_seconds}s")
        print(f"   Endpoints:  {', '.join(self.profile.endpoints)}")
        print(f"{'='*60}\n")

        self._running = True
        self.stats["start_time"] = datetime.now()
        
        connector = aiohttp.TCPConnector(limit=100, limit_per_host=50)
        
        async with aiohttp.ClientSession(connector=connector) as session:
            end_time = time.time() + self.profile.duration_seconds
            interval = 1.0 / self.profile.rps
            request_count = 0
            
            # Progress tracking
            progress_interval = max(1, self.profile.duration_seconds // 10)
            last_progress = 0
            
            while time.time() < end_time and self._running:
                # Select random endpoint
                endpoint = random.choice(self.profile.endpoints)
                
                # Fire and forget request
                asyncio.create_task(self._make_request(session, endpoint))
                request_count += 1
                
                # Progress indicator
                elapsed = int(time.time() - (end_time - self.profile.duration_seconds))
                if elapsed > last_progress and elapsed % progress_interval == 0:
                    last_progress = elapsed
                    pct = (elapsed / self.profile.duration_seconds) * 100
                    print(f"   ⏳ Progress: {pct:.0f}% ({elapsed}s / {self.profile.duration_seconds}s) - {self.stats['total_requests']} requests")
                
                await asyncio.sleep(interval)
            
            # Wait for pending requests to complete
            print("\n   ⏳ Waiting for pending requests...")
            await asyncio.sleep(3)
        
        self.stats["end_time"] = datetime.now()
        self._print_results()

    def stop(self):
        """Stop the load generator."""
        self._running = False
        print("\n⚠️  Stopping load generator...")

    def _print_results(self):
        """Print test results summary."""
        duration = (self.stats["end_time"] - self.stats["start_time"]).total_seconds()
        total = self.stats["total_requests"]
        success = self.stats["success"]
        failure = self.stats["failure"]
        success_rate = (success / total * 100) if total > 0 else 0
        actual_rps = total / duration if duration > 0 else 0
        
        # Calculate percentiles
        latencies = sorted(self.stats["latencies"]) if self.stats["latencies"] else [0]
        p50 = latencies[int(len(latencies) * 0.50)] if latencies else 0
        p95 = latencies[int(len(latencies) * 0.95)] if latencies else 0
        p99 = latencies[int(len(latencies) * 0.99)] if latencies else 0
        avg = sum(latencies) / len(latencies) if latencies else 0
        
        print(f"\n{'='*60}")
        print(f"📊 Load Test Results")
        print(f"{'='*60}")
        print(f"   Duration:       {duration:.1f}s")
        print(f"   Total Requests: {total}")
        print(f"   Actual RPS:     {actual_rps:.1f}")
        print(f"\n   ✅ Success:      {success} ({success_rate:.1f}%)")
        print(f"   ❌ Failures:     {failure}")
        
        print(f"\n   📈 Latency Statistics:")
        print(f"      Average: {avg:.2f}ms")
        print(f"      P50:     {p50:.2f}ms")
        print(f"      P95:     {p95:.2f}ms")
        print(f"      P99:     {p99:.2f}ms")
        
        if self.stats["status_codes"]:
            print(f"\n   🔢 Status Codes:")
            for code, count in sorted(self.stats["status_codes"].items()):
                print(f"      {code}: {count}")
        
        if self.stats["errors"] and len(self.stats["errors"]) <= 5:
            print(f"\n   ⚠️  Sample Errors:")
            for err in self.stats["errors"][:5]:
                print(f"      - {err}")
        
        print(f"{'='*60}\n")
        
        # Return summary for programmatic use
        return {
            "success_rate": success_rate,
            "avg_latency": avg,
            "p95_latency": p95,
            "p99_latency": p99,
            "total_requests": total,
            "rps": actual_rps,
        }


def main():
    parser = argparse.ArgumentParser(
        description="Load Generator for MicroShop Chaos Engineering",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Profiles:
  steady   - Low steady traffic (10 RPS, 5 min) - baseline collection
  shopping - Moderate traffic (25 RPS, 3 min) - simulate shopping
  peak     - High load (50 RPS, 1 min) - stress testing
  chaos    - Extended load (30 RPS, 10 min) - chaos experiments
  spike    - Burst traffic (100 RPS, 30 sec) - spike test

Examples:
  python load-generator.py --profile steady
  python load-generator.py --profile chaos --url http://localhost:8080 -v
        """
    )
    
    parser.add_argument(
        "--url", "-u",
        default="http://localhost:8080",
        help="Base URL of MicroShop (default: http://localhost:8080)"
    )
    parser.add_argument(
        "--profile", "-p",
        default="steady",
        choices=PROFILES.keys(),
        help="Load profile to use (default: steady)"
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Show individual request results"
    )
    parser.add_argument(
        "--list-profiles",
        action="store_true",
        help="List available profiles and exit"
    )
    
    args = parser.parse_args()
    
    if args.list_profiles:
        print("\nAvailable Load Profiles:")
        print("-" * 50)
        for name, profile in PROFILES.items():
            print(f"  {name:12} - {profile.description}")
            print(f"               RPS: {profile.rps}, Duration: {profile.duration_seconds}s")
        print()
        sys.exit(0)
    
    profile = PROFILES[args.profile]
    generator = LoadGenerator(args.url, profile, verbose=args.verbose)
    
    try:
        asyncio.run(generator.run())
    except KeyboardInterrupt:
        generator.stop()
        print("\n✅ Load generator stopped by user")


if __name__ == "__main__":
    main()
