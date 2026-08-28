jest.mock('../cloud/repositories/aiCostRepository');
const aiCostRepository = require('../cloud/repositories/aiCostRepository');
const adminService = require('../cloud/services/adminService');

afterEach(() => jest.clearAllMocks());

describe('adminService.exportAICosts', () => {
  it('sums tokens and cost across every row, skipping null costUSD from the total', async () => {
    aiCostRepository.listAll.mockResolvedValue([
      { objectId: '1', totalTokens: 150, costUSD: 0.001 },
      { objectId: '2', totalTokens: 300, costUSD: 0.002 },
      { objectId: '3', totalTokens: 50, costUSD: null },
    ]);

    const result = await adminService.exportAICosts();

    expect(result.rows).toHaveLength(3);
    expect(result.summary).toEqual({ rowCount: 3, totalTokens: 500, totalCostUSD: 0.003 });
  });

  it('passes sinceDate through to the repository', async () => {
    aiCostRepository.listAll.mockResolvedValue([]);
    const sinceDate = new Date('2026-08-01T00:00:00.000Z');

    await adminService.exportAICosts({ sinceDate });

    expect(aiCostRepository.listAll).toHaveBeenCalledWith({ sinceDate });
  });

  it('returns a zeroed summary for no rows', async () => {
    aiCostRepository.listAll.mockResolvedValue([]);

    const result = await adminService.exportAICosts();

    expect(result).toEqual({ rows: [], summary: { rowCount: 0, totalTokens: 0, totalCostUSD: 0 } });
  });
});
