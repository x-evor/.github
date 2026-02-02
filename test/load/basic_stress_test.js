import http from 'k6/http';
import { check, sleep, group } from 'k6';

// ----------------------------------------------------------------------------
// Load Test Configuration
// ----------------------------------------------------------------------------
export let options = {
    stages: [
        { duration: '30s', target: 20 },  // Ramp-up to 20 users
        { duration: '2m', target: 100 }, // Stay at 100 users (Stress Test)
        { duration: '30s', target: 0 },   // Ramp-down
    ],
    thresholds: {
        http_req_duration: ['p(95)<500'], // 95% of requests should be below 500ms
        http_req_failed: ['rate<0.01'],   // Error rate should be less than 1%
    },
};

const BASE_URL = __ENV.BASE_URL || 'https://console.svc.plus';
const ACCOUNTS_URL = __ENV.ACCOUNTS_URL || 'https://accounts.svc.plus';

// ----------------------------------------------------------------------------
// Test Scenarios
// ----------------------------------------------------------------------------

export default function () {
    group('Auth Session Check', function () {
        let res = http.get(`${ACCOUNTS_URL}/api/auth/session`);
        check(res, {
            'session status is 200': (r) => r.status === 200,
        });
    });

    group('Admin Metrics Payload', function () {
        // Note: Requires Auth headers if tested against real prod
        let res = http.get(`${ACCOUNTS_URL}/api/admin/users/metrics`);
        check(res, {
            'metrics status is 200 or 401': (r) => r.status === 200 || r.status === 401,
        });
    });

    sleep(1);
}
