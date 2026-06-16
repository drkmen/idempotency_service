# frozen_string_literal: true

# Durable storage of committed idempotency responses.
#
# Columns:
# - idempotency_key: string (unique)
# - fingerprint: string
# - response_body: jsonb
# - response_status: integer
# - expires_at: datetime
class IdempotencyRecord < ApplicationRecord
  validates :idempotency_key, presence: true, uniqueness: true
  validates :fingerprint, presence: true
  validates :response_status, presence: true
end
