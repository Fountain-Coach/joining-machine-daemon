# Security boundary

Please do not report credentials, private Store data, machine identities, or
production host details in public issues. Use the repository's private security
contact configured on GitHub for a suspected vulnerability.

This repository deliberately contains only the portable responder/runtime and
typed host-injection boundary. It does not contain the FountainStore adapter,
SecretStore access, signing keys, deployment credentials, service-unit data,
or target addresses. A public build is not an admission proof and must not be
installed into a sensitive realm without the consuming system's authorization,
artifact verification, and read-back gates.
