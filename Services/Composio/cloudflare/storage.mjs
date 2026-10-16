// D1 is the durable authority across isolates. Never expire or take over a
// reservation: a stopped Worker may have already dispatched its external effect.
export class D1Storage {
  constructor(database) {
    if (!database || typeof database.withSession !== 'function') throw new Error('The DB D1 binding is required.');
    this.database = database;
  }
  async initialize() { /* Apply the checked-in migration before serving traffic. */ }
  session() { return this.database.withSession('first-primary'); }
  async createInstallation(tokenHash, userID) {
    await this.session().prepare('INSERT INTO installations (token_hash, user_id) VALUES (?, ?)').bind(tokenHash, userID).run();
  }
  async getInstallation(tokenHash) {
    const row = await this.session().prepare('SELECT user_id FROM installations WHERE token_hash = ?').bind(tokenHash).first();
    return row ? { userID: row.user_id } : null;
  }
  async requestVoiceActivation(userID) {
    const result = await this.session().prepare('INSERT INTO voice_activation_requests (user_id) VALUES (?) ON CONFLICT (user_id) DO UPDATE SET requested_at = CURRENT_TIMESTAMP').bind(userID).run();
    if (!result.success) throw new Error('Voice activation could not be requested.');
  }
  async getCatalog(slug, version) {
    return this.session().prepare('SELECT payload_json FROM public_catalogs WHERE toolkit_slug = ? AND toolkit_version = ?').bind(slug, version).first('payload_json');
  }
  async reserveExecution(userID, requestID, fingerprint) {
    const result = await this.session().prepare("INSERT INTO executions (user_id, request_id, fingerprint, state) VALUES (?, ?, ?, 'pending') ON CONFLICT (user_id, request_id) DO NOTHING").bind(userID, requestID, fingerprint).run();
    if (!result.success || !Number.isInteger(result.meta?.changes)) throw new Error('The request reservation was not verified.');
    return result.meta.changes === 1;
  }
  async getExecution(userID, requestID) {
    const row = await this.session().prepare('SELECT fingerprint, state, receipt_json FROM executions WHERE user_id = ? AND request_id = ?').bind(userID, requestID).first();
    return row ? { fingerprint: row.fingerprint, state: row.state, ...(row.receipt_json ? { receipt: JSON.parse(row.receipt_json) } : {}) } : null;
  }
  async saveExecution(userID, requestID, value) {
    // The service supplies only a sanitized receipt, never provider result data.
    if (value.receipt?.payload && Object.hasOwn(value.receipt.payload, 'data')) throw new Error('Provider content cannot be persisted.');
    const result = await this.session().prepare("UPDATE executions SET state = ?, receipt_json = ? WHERE user_id = ? AND request_id = ? AND fingerprint = ? AND state = 'pending'").bind(value.state, value.receipt ? JSON.stringify(value.receipt) : null, userID, requestID, value.fingerprint).run();
    if (!result.success || result.meta?.changes !== 1) throw new Error('The durable receipt was not verified.');
  }
}
