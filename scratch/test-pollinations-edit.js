async function test() {
  const form = new FormData();
  form.append("prompt", "a cat");
  form.append("model", "microsoft/mai-image-2.6");

  const res = await fetch("https://gen.pollinations.ai/v1/images/edits", {
    method: "POST",
    headers: { "Authorization": "Bearer fakekey" },
    body: form
  });
  console.log(res.status, res.statusText);
  console.log(await res.text());
}
test();