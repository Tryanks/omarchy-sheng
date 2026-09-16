# ARM application sources

The original overlay synchronized official Omarchy edge with `Usage = Sync` to
keep graphics updates source-qualified. Native Omarchy's package picker still
listed those packages, but installed unqualified names. An official-only target
such as Typora therefore appeared in the picker and then failed to install.
Ghostty was a separate omission: neither ALARM nor official edge supplied it;
the Omarchy Mac ARM supplementary repository did.

The overlay now adds that supplement after ALARM and routes the native package
picker through a shared source resolver. Ordinary applications use the normal
install repositories; unresolved names fall back to explicit `omarchy/name`.
The same resolver is used when building the default application set. Virtual
providers are supported, and unversioned `dotnet-runtime` selects the modern
`dotnet-runtime-bin`, rather than the supplement's legacy .NET 2.1 provider.

Application sources: <https://github.com/omarchy-mac/omarchy-pkgs-aarch64>.
Current supplementary edge archives are unsigned. `Optional TrustedOnly` is
scoped to this new repository, accepting unsigned packages but requiring trust
for any signed packages. ALARM and official Omarchy signature policy is retained.
The official Omarchy/settings pair and graphics targets remain explicit during
managed full system updates. Do not substitute an unqualified `pacman -Syu`
for `omarchy update`; the supplement also publishes Mac-specific desktop packages.

On the tablet, Ghostty 1.3.1-1 and its two integration packages installed without
replacing any desktop/graphics packages. Downloaded archives matched GitHub's
published SHA-256 digests. Ghostty initialized OpenGL 4.6, loaded the user's
Omarchy theme and launched its shell successfully. This does not validate every
application in the supplement; OBS, for example, is built without browser-source
support. Existing manually installed gaming software is unchanged.

Run `bash tests/arm-package-sources.sh` on an updated native ARM rootfs for a
read-only repository and full-upgrade selection check. Published preview.2
images predate this change; installing Ghostty on the test tablet does not alter
those downloadable images or their recorded package manifests.
