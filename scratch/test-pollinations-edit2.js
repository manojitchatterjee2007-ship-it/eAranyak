async function test() {
  const form = new FormData();
  form.append("prompt", "a cat");
  form.append("model", "microsoft/mai-image-2.6");

  // try appending base64
  form.append("image", "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=");

  const res = await fetch("https://gen.pollinations.ai/v1/images/edits", {
    method: "POST",
    headers: { "Authorization": "Bearer fakekey" },
    body: form
  });
  console.log(res.status, res.statusText);
  console.log(await res.text());
}
test();