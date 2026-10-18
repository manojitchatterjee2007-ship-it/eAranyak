async function test() {
  const body = {
    prompt: "a cat",
    model: "microsoft/mai-image-2.6",
    image: "https://placekitten.com/200/300"
  };

  const res = await fetch("https://gen.pollinations.ai/v1/images/edits", {
    method: "POST",
    headers: {
      "Authorization": "Bearer fakekey",
      "Content-Type": "application/json"
    },
    body: JSON.stringify(body)
  });
  console.log(res.status, res.statusText);
  console.log(await res.text());
}
test();