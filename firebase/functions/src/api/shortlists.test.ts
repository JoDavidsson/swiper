import { shortlistsCreatePost } from "./shortlists";

const mockReq = (body: object) => ({ body } as any);
const mockRes = () => ({ status: jest.fn().mockReturnThis(), json: jest.fn() } as any);

describe("shortlists create", () => {
  it("returns 400 when sessionId missing", async () => {
    const req = mockReq({});
    const res = mockRes();
    await shortlistsCreatePost(req, res);
    expect(res.status).toHaveBeenCalledWith(400);
  });
});
