async function test() {
  const body = {
    prompt: "a cat",
    model: "tongyi-mai/z-image-turbo"
  };
  const res = await fetch("https://gen.pollinations.ai/v1/images/generations", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body)
  });
  console.log(res.status, res.statusText);
  console.log(await res.text());
}
test();