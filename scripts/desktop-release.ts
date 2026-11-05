type ReleaseInput = {
  version: string;
  tag: string;
  filename: string;
  signature: string;
  commit: string;
  publishedAt: string;
};

export function desktopManifest(input: ReleaseInput): {
  version: string;
  notes: string;
  pub_date: string;
  platforms: Record<string, { signature: string; url: string }>;
} {
  const { version, tag, filename, commit, publishedAt } = input;
  const signature = input.signature.trim();
  if (!/^\d+\.\d+\.\d+$/.test(version) || tag !== `desktop-v${version}`)
    throw new Error("Release tag must match the desktop version");
  if (filename !== `KB OneMail_${version}_x64-setup.exe`)
    throw new Error("Unexpected desktop installer filename");
  if (!signature || signature.length > 16_384)
    throw new Error("A bounded updater signature is required");
  if (
    !/^[a-f0-9]{40}$/i.test(commit) ||
    !Number.isFinite(Date.parse(publishedAt))
  )
    throw new Error("Exact source commit and publication date are required");
  return {
    version,
    notes: `KB OneMail ${version} unsigned Windows personal preview. Source: ${commit}. Update signatures do not provide Windows publisher signing.`,
    pub_date: new Date(publishedAt).toISOString(),
    platforms: {
      "windows-x86_64": {
        signature,
        url: `https://github.com/KB01111/kb-onemail/releases/download/${tag}/${encodeURIComponent(filename.replaceAll(" ", "."))}`,
      },
    },
  };
}

if (import.meta.main) {
  const { basename, dirname, join } = await import("node:path");
  const { createHash } = await import("node:crypto");
  const [installer, tag, commit] = Bun.argv.slice(2);
  if (!installer || !tag || !commit)
    throw new Error(
      "Usage: bun scripts/desktop-release.ts <installer> <desktop-vVERSION> <commit>",
    );
  const config = await Bun.file(
    new URL("../desktop/src-tauri/tauri.conf.json", import.meta.url),
  ).json();
  const signature = await Bun.file(`${installer}.sig`).text();
  const manifest = desktopManifest({
    version: process.env.KB_ONEMAIL_RELEASE_VERSION ?? config.version,
    tag,
    commit,
    filename: basename(installer),
    signature,
    publishedAt: new Date().toISOString(),
  });
  const digest = createHash("sha256")
    .update(new Uint8Array(await Bun.file(installer).arrayBuffer()))
    .digest("hex");
  await Bun.write(`${installer}.sha256`, `${digest}  ${basename(installer)}\n`);
  await Bun.write(
    join(dirname(installer), "latest.json"),
    `${JSON.stringify(manifest, null, 2)}\n`,
  );
  console.log(
    `Prepared verified-update manifest and SHA-256 for ${basename(installer)}`,
  );
}
