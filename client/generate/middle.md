The index.svelte component handles the logon process and either redirects to a feide.cgi-script for
FEIDE-authentication (OAuth) or logs on using the built-in AuroraID account.

After login, the code redirects to the Main.svelte-component which is the central "hub" for most of
what is done in the application.

FEIDE-authentication is performed by the public/feide.cgi-script written in Perl. It runs on the web-server and converts the
credentials it receives into a set of AURORA crumbs credentials that are forwarded to the AURORA web-client. In this way the
credentials exposed to the user browser are only valid for AURORA and temporary in nature.

All the cookies are base64 encoded before they are stored or served to the application. The reason for this is that the feide.cgi
perl-script did not handle having certain characters in the cookie values through the CGI-library and its cookie-routines. It then
resulted in issues with the transport between it and the web-client application. The easiest solution was therefore to encode
all cookies into and out of the browser seemlessly for the application. This makes reading cookie contents manually in the
browser through the developer window a bit like reading ancient egyptian hieroglyphs before Champollion came along.
