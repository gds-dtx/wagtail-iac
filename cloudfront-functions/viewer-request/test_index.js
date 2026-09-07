const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const handler = vm.runInNewContext(
  `${fs.readFileSync(path.join(__dirname, "index.js"), "utf8")}\nhandler;`,
);

function eventFor({
  host = "www.example.com",
  uri = "/help",
  querystring = {},
} = {}) {
  return {
    request: {
      uri,
      querystring,
      headers: {
        host: {
          value: host,
        },
      },
    },
  };
}

test("returns the original request when the host is already apex", () => {
  const event = eventFor({ host: "example.com" });

  assert.equal(handler(event), event.request);
});

test("returns the original request when the host header is missing", () => {
  const event = eventFor();
  delete event.request.headers.host;

  assert.equal(handler(event), event.request);
});

test("redirects www hosts to apex", () => {
  const response = handler(
    eventFor({ host: "www.example.com", uri: "/about" }),
  );

  assert.equal(response.statusCode, 301);
  assert.equal(response.statusDescription, "Moved Permanently");
  assert.equal(response.headers.location.value, "https://example.com/about");
});

test("blocks known bad paths", () => {
  const badPaths = [
    "/.env",
    "/wp-login.php",
    "/.git/config",
    "/ADMIN.PHP?debug=true#section",
  ];

  for (const uri of badPaths) {
    const response = handler(eventFor({ host: "example.com", uri }));

    assert.equal(response.statusCode, 403, uri);
    assert.equal(response.statusDescription, "Forbidden", uri);
    assert.equal(response.body, "Access denied", uri);
  }
});

test("redirects the security.txt well-known URIs", () => {
  const securityTxtUris = [
    "/security.txt",
    "/.well-known/security.txt",
    "/.well_known/security.txt",
    "/SECURITY.TXT?utm=1#frag",
  ];

  for (const uri of securityTxtUris) {
    const response = handler(eventFor({ host: "example.com", uri }));

    assert.equal(response.statusCode, 302, uri);
    assert.equal(
      response.headers.location.value,
      "https://vulnerability-reporting.service.security.gov.uk/.well-known/security.txt",
      uri,
    );
  }
});

test("does not redirect ordinary paths that merely start with security", () => {
  const contentUris = [
    "/security-architect/",
    "/security-architect/skills/",
    "/security-operations/",
    "/securitytxt-guidance/",
    "/xwell-known/security.txt",
    // Only the two canonical files are the security.txt: a bare /security
    // or /.well-known/security is a page like any other.
    "/security",
    "/security/",
    "/.well-known/security",
  ];

  for (const uri of contentUris) {
    const event = eventFor({ host: "example.com", uri });

    assert.equal(handler(event), event.request, uri);
  }
});
