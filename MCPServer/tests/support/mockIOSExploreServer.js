import http from "node:http";
export async function withMockIOSExploreServer(route, run) {
    const requests = [];
    const server = http.createServer((req, res) => {
        let body = "";
        req.setEncoding("utf8");
        req.on("data", chunk => {
            body += chunk;
        });
        req.on("end", () => {
            const parsed = JSON.parse(body);
            requests.push(parsed);
            const response = route(parsed);
            const send = () => {
                res.statusCode = response.status ?? 200;
                res.setHeader("Content-Type", typeof response.body === "string" ? "text/plain" : "application/json");
                res.end(typeof response.body === "string" ? response.body : JSON.stringify(response.body));
            };
            if (response.delayMs && response.delayMs > 0) {
                setTimeout(send, response.delayMs);
            }
            else {
                send();
            }
        });
    });
    await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
    const address = server.address();
    try {
        return await run({ baseURL: `http://127.0.0.1:${address.port}/`, requests });
    }
    finally {
        await new Promise(resolve => server.close(() => resolve()));
    }
}
