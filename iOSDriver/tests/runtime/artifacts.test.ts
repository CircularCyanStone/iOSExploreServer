import { describe, expect, test } from "vitest";
import { ArtifactDecoder } from "../../src/runtime/artifacts.js";

const PNG = Buffer.from([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
  0x00, 0x00, 0x00, 0x00
]);

describe("ArtifactDecoder", () => {
  test("只将 ui.screenshot 的合法 PNG 解码成 image artifact 并从 data 移除 image", () => {
    const decoder = new ArtifactDecoder({ maxDecodedBytes: 1024 });
    const result = decoder.decode("ui.screenshot", {
      image: PNG.toString("base64"),
      format: "png",
      mimeType: "image/png",
      width: 2,
      height: 3,
      scale: 2
    });

    expect(result).toMatchObject({
      ok: true,
      data: { format: "png", mimeType: "image/png", width: 2, height: 3, scale: 2 },
      artifacts: [{
        kind: "image",
        mimeType: "image/png",
        metadata: { format: "png", mimeType: "image/png", width: 2, height: 3, scale: 2 }
      }]
    });
    if (result.ok) expect(Buffer.from(result.artifacts[0]!.data)).toEqual(PNG);
  });

  test("非截图 action 不解释 image 字段", () => {
    const data = { image: PNG.toString("base64"), format: "png" };
    expect(new ArtifactDecoder().decode("echo", data)).toEqual({ ok: true, data, artifacts: [] });
  });

  test.each([
    ["非严格 base64", { image: "not base64!", format: "png" }],
    ["错误 PNG signature", { image: Buffer.from("not png").toString("base64"), format: "png" }],
    ["错误 format", { image: PNG.toString("base64"), format: "jpeg" }],
    ["错误 MIME", { image: PNG.toString("base64"), format: "png", mimeType: "image/jpeg" }],
    ["非正整数 width", { image: PNG.toString("base64"), format: "png", width: 0 }],
    ["非有限整数 height", { image: PNG.toString("base64"), format: "png", height: 1.5 }]
  ])("%s 返回 artifact_decode_failed 且不保留 image", (_name, data) => {
    const result = new ArtifactDecoder().decode("ui.screenshot", data);

    expect(result).toMatchObject({
      ok: false,
      error: { source: "artifact", code: "artifact_decode_failed", action: "ui.screenshot" }
    });
    expect(result.data).not.toHaveProperty("image");
  });

  test("拒绝超过 decoded bytes 上限的 PNG", () => {
    const result = new ArtifactDecoder({ maxDecodedBytes: PNG.length - 1 }).decode("ui.screenshot", {
      image: PNG.toString("base64"),
      format: "png"
    });

    expect(result).toMatchObject({ ok: false, error: { code: "artifact_decode_failed" } });
  });
});
