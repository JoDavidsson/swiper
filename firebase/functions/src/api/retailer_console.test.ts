import { Request } from "express";

// ---------------------------------------------------------------------------
// Mocks - must mock firebase-admin module before importing retailer_console
// ---------------------------------------------------------------------------

const mockTimestampFromMillis = jest.fn((ms: number) => ({
  toMillis: () => ms,
  toDate: () => new Date(ms),
}));

// Create a mock Timestamp class
const MockTimestamp = jest.fn().mockImplementation(() => ({
  toMillis: () => 0,
  toDate: () => new Date(),
}));
(MockTimestamp as any).fromMillis = mockTimestampFromMillis;

// Mock Firestore instance
const mockFirestoreInstance = {
  collection: jest.fn(),
};
// Make the mock handle both callable form and property access
const mockFirestore = jest.fn(() => mockFirestoreInstance) as any;
mockFirestore.Timestamp = MockTimestamp;

jest.mock("firebase-admin", () => ({
  firestore: mockFirestore,
  initializeApp: jest.fn(),
}));

// Mock requireUserAuth
const mockRequireUserAuth = jest.fn();
jest.mock("../middleware/require_user_auth", () => ({
  requireUserAuth: () => mockRequireUserAuth(),
}));

import { retailerInsightsGet } from "./retailer_console";

const mockReq = (query: object = {}) => ({ query, body: {} } as unknown as Request);

interface MockResponse {
  status: jest.Mock;
  json: jest.Mock;
}

const mockRes = (): MockResponse => ({
  status: jest.fn().mockReturnThis(),
  json: jest.fn().mockReturnThis(),
});

function makeEmptyFirestoreMock() {
  const mock = {
    where: jest.fn().mockReturnThis(),
    orderBy: jest.fn().mockReturnThis(),
    limit: jest.fn().mockReturnThis(),
    get: jest.fn().mockResolvedValue({ empty: true, docs: [] }),
  };
  return mock;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("retailerInsightsGet", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockRequireUserAuth.mockResolvedValue({
      uid: "user-1",
      email: "test@test.com",
      displayName: "Test",
      photoUrl: null,
    });
    // Reset the collection mock to return fresh mocks each time
    mockFirestoreInstance.collection.mockImplementation(() => makeEmptyFirestoreMock());
  });

  it("returns 401 when user is not authenticated", async () => {
    mockRequireUserAuth.mockResolvedValue(null);
    const req = mockReq();
    const res = mockRes();
    await retailerInsightsGet(req, res as never);
    expect(res.status).toHaveBeenCalledWith(401);
    expect(res.json).toHaveBeenCalledWith({ error: "Authentication required" });
  });

  it("returns 404 when user has no retailer access", async () => {
    const retailersMock = makeEmptyFirestoreMock();
    retailersMock.get.mockResolvedValue({ empty: true, docs: [] });
    mockFirestoreInstance.collection.mockImplementation((name: string) => {
      if (name === "retailers") return retailersMock;
      return makeEmptyFirestoreMock();
    });

    const req = mockReq({});
    const res = mockRes();
    await retailerInsightsGet(req, res as never);
    expect(res.status).toHaveBeenCalledWith(404);
  });

  it("returns 500 on unexpected error", async () => {
    mockRequireUserAuth.mockResolvedValue({
      uid: "user-1",
      email: "test@test.com",
      displayName: "Test",
      photoUrl: null,
    });
    mockFirestoreInstance.collection.mockImplementation(() => {
      throw new Error("Firestore error");
    });

    const req = mockReq({});
    const res = mockRes();
    await retailerInsightsGet(req, res as never);
    expect(res.status).toHaveBeenCalledWith(500);
    expect(res.json).toHaveBeenCalledWith({ error: "Failed to load insights" });
  });
});
