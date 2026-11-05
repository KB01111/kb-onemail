import { expect, test } from "bun:test";
import { desktopManifest } from "./desktop-release";

test("packaging and the native runtime share the public update verification key", async () => {
  const config = await Bun.file(
    new URL("../desktop/src-tauri/tauri.conf.json", import.meta.url),
  ).json();
  const publicKey = (
    await Bun.file(new URL("../desktop/updater.pub", import.meta.url)).text()
  ).trim();
  expect(config.plugins.updater?.pubkey).toBe(publicKey);
  expect(config.plugins.updater?.endpoints).toEqual([
    "https://github.com/KB01111/kb-onemail/releases/download/desktop-preview/latest.json",
  ]);
});

const input = {
  version: "0.3.0",
  tag: "desktop-v0.3.0",
  filename: "KB OneMail_0.3.0_x64-setup.exe",
  signature: "a-valid-updater-signature",
  commit: "a".repeat(40),
  publishedAt: "2026-10-30T20:00:00.000Z",
};

test("desktop channel targets an immutable versioned installer and carries its signature", () => {
  const manifest = desktopManifest(input);
  expect(manifest.version).toBe("0.3.0");
  expect(manifest.platforms["windows-x86_64"].url).toBe(
    "https://github.com/KB01111/kb-onemail/releases/download/desktop-v0.3.0/KB.OneMail_0.3.0_x64-setup.exe",
  );
  expect(manifest.platforms["windows-x86_64"].signature).toBe(input.signature);
  expect(manifest.notes).toContain(input.commit);
  expect(manifest.notes).toContain("unsigned");
});

test("release manifest rejects unsigned, mutable, mismatched or path-injected artifacts", () => {
  for (const change of [
    { signature: " " },
    { tag: "desktop-preview" },
    { tag: "desktop-v0.2.1" },
    { version: "0.3.0/evil" },
    { filename: "../KB OneMail_0.3.0_x64-setup.exe" },
    { filename: "KB OneMail_0.2.1_x64-setup.exe" },
    { commit: "branch-name" },
    { publishedAt: "yesterday" },
  ])
    expect(() => desktopManifest({ ...input, ...change })).toThrow();
});
