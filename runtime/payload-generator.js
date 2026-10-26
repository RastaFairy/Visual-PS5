'use strict';
(function attachPayloadCodegen(root) {
  const C_SOURCE = `#include <stddef.h>
#include <string.h>

typedef struct notify_request {
  char useless1[45];
  char message[3075];
} notify_request_t;

int sceKernelSendNotificationRequest(int, notify_request_t*, size_t, int);

int main(void) {
  static const char message[] = "Visual-PS5 payload loaded";
  notify_request_t request = {0};
  memcpy(request.message, message, sizeof(message));
  return sceKernelSendNotificationRequest(0, &request, sizeof(request), 0);
}
`;

  const CPP_SOURCE = `#include <stddef.h>
#include <string.h>

struct notify_request {
  char useless1[45];
  char message[3075];
};

extern "C" int sceKernelSendNotificationRequest(int, notify_request*, size_t, int);

int main() {
  static constexpr char message[] = "Visual-PS5 payload loaded";
  notify_request request{};
  memcpy(request.message, message, sizeof(message));
  return sceKernelSendNotificationRequest(0, &request, sizeof(request), 0);
}
`;

  function generate(language = 'c') {
    if (language === 'c') return C_SOURCE;
    if (language === 'cpp') return CPP_SOURCE;
    throw new Error(`Lenguaje de payload no compatible: ${String(language)}`);
  }
  const api = { version: 1, generate };
  if (root) root.PS5HSPayloadCodegen = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof globalThis === 'object' ? globalThis : null);
