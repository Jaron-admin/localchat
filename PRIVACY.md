# LocalChat privacy

LocalChat is an independent fork of LocalSend. It is designed for direct communication
between devices on the same local network, without a central account or message server.

The app advertises its device alias, network address and protocol information to nearby
devices. Use an alias that you are comfortable sharing on the network. Discovery does
not prove a device belongs to a particular person.

Settings, device credentials and any supported history are stored in LocalChat's own
local application data directory. Files are saved to the location you choose. Local
storage is protected by your operating-system account and device security settings;
the app does not promise encrypted storage at rest.

The inherited public WebRTC signaling option remains disabled. LocalChat does not
enable LocalSend's in-app purchase integration. Opening external links in the About
or Settings pages uses your browser and connects to the linked website.

Mobile reception depends on the app being active; this version does not promise
background or locked-screen delivery. See the repository for the current implementation
and validation status: <https://github.com/Jaron-admin/localchat>.
