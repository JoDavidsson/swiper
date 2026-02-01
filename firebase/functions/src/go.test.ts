import { goHandler } from "./go";

const mockReq = (path: string) => ({ path, query: {}, headers: {} } as any);
const mockRes = () => ({ status: jest.fn().mockReturnThis(), send: jest.fn(), redirect: jest.fn() } as any);

describe("go", () => {
  it("returns 400 when path has no itemId", async () => {
    const req = mockReq("/go/");
    const res = mockRes();
    await goHandler(req, res);
    expect(res.status).toHaveBeenCalledWith(400);
  });
});
