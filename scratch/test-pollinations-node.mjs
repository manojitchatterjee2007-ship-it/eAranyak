import fs from 'fs';

async function test() {
  const form = new FormData();
  form.append("prompt", "a cat");
  form.append("model", "microsoft/mai-image-2.6");

  // A tiny 1x1 png
  const buf = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", 'base64');
  const blob = new Blob([buf], { type: "image/png" });
  form.append("image", blob, "source.png");

  const res = await fetch("https://gen.pollinations.ai/v1/images/edits", {
    method: "POST",
    headers: { "Authorization": "Bearer fakekey" },
    body: form
  });
  console.log(res.status, res.statusText);
  console.log(await res.text());
}
test();