const { createFakeParse } = require('./helpers/fakeParse');

const { Parse, cloudRegistry } = createFakeParse();
global.Parse = Parse;

jest.mock('../cloud/services/adminService');
const adminService = require('../cloud/services/adminService');

require('../cloud/functions/adminExportAICosts');

const ORIGINAL_SECRET = process.env.MMCOACH_ADMIN_SECRET;

afterEach(() => {
  jest.clearAllMocks();
  process.env.MMCOACH_ADMIN_SECRET = ORIGINAL_SECRET;
});

describe('mmAdminExportAICosts', () => {
  it('rejects when MMCOACH_ADMIN_SECRET is not configured server-side', async () => {
    delete process.env.MMCOACH_ADMIN_SECRET;

    await expect(
      cloudRegistry.mmAdminExportAICosts({ params: { adminSecret: 'anything' } })
    ).rejects.toMatchObject({ code: Parse.Error.INVALID_SESSION_TOKEN });
    expect(adminService.exportAICosts).not.toHaveBeenCalled();
  });

  it('rejects a missing or wrong adminSecret without calling the service', async () => {
    process.env.MMCOACH_ADMIN_SECRET = 'correct-secret';

    await expect(cloudRegistry.mmAdminExportAICosts({ params: {} })).rejects.toMatchObject({
      code: Parse.Error.INVALID_SESSION_TOKEN,
    });
    await expect(
      cloudRegistry.mmAdminExportAICosts({ params: { adminSecret: 'wrong' } })
    ).rejects.toMatchObject({ code: Parse.Error.INVALID_SESSION_TOKEN });
    expect(adminService.exportAICosts).not.toHaveBeenCalled();
  });

  it('returns the export when the secret matches, with no sinceDate by default', async () => {
    process.env.MMCOACH_ADMIN_SECRET = 'correct-secret';
    adminService.exportAICosts.mockResolvedValue({
      rows: [],
      summary: { rowCount: 0, totalTokens: 0, totalCostUSD: 0 },
    });

    const result = await cloudRegistry.mmAdminExportAICosts({
      params: { adminSecret: 'correct-secret' },
    });

    expect(adminService.exportAICosts).toHaveBeenCalledWith({ sinceDate: undefined });
    expect(result.summary.rowCount).toBe(0);
  });

  it('converts sinceDays into a sinceDate roughly that many days ago', async () => {
    process.env.MMCOACH_ADMIN_SECRET = 'correct-secret';
    adminService.exportAICosts.mockResolvedValue({
      rows: [],
      summary: { rowCount: 0, totalTokens: 0, totalCostUSD: 0 },
    });

    const before = Date.now();
    await cloudRegistry.mmAdminExportAICosts({
      params: { adminSecret: 'correct-secret', sinceDays: 7 },
    });

    const { sinceDate } = adminService.exportAICosts.mock.calls[0][0];
    const expectedMs = 7 * 24 * 60 * 60 * 1000;
    expect(before - sinceDate.getTime()).toBeGreaterThanOrEqual(expectedMs - 1000);
    expect(before - sinceDate.getTime()).toBeLessThanOrEqual(expectedMs + 1000);
  });
});
