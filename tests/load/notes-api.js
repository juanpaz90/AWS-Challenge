// Load test for the Notes API through the gateway (Phase 9 check 6: HPA scale-out).
//   k6 run tests/load/notes-api.js                 # defaults: 20 VUs for 3m
//   BASE_URL=https://api.localtest.me VUS=30 DURATION=5m k6 run tests/load/notes-api.js
import http from "k6/http";
import { check } from "k6";

const BASE_URL = __ENV.BASE_URL || "https://api.localtest.me";

export const options = {
  vus: Number(__ENV.VUS || 20),
  duration: __ENV.DURATION || "3m",
  // The local gateway certificate is issued by the throwaway local CA (test only).
  insecureSkipTLSVerify: true,
  thresholds: {
    http_req_failed: ["rate<0.01"], // availability SLO territory (docs/slo.md)
    http_req_duration: ["p(95)<300"], // latency SLO
  },
};

export default function () {
  const list = http.get(`${BASE_URL}/notes?limit=20`, { tags: { name: "GET /notes" } });
  check(list, { "list 200": (r) => r.status === 200 });

  const created = http.post(
    `${BASE_URL}/notes`,
    JSON.stringify({ title: "load", content: `vu ${__VU} iter ${__ITER}` }),
    { headers: { "Content-Type": "application/json" }, tags: { name: "POST /notes" } },
  );
  check(created, { "create 201": (r) => r.status === 201 });

  if (created.status === 201) {
    const id = created.json("id");
    const read = http.get(`${BASE_URL}/notes/${id}`, { tags: { name: "GET /notes/{id}" } });
    check(read, { "read 200": (r) => r.status === 200 });
  }
}
