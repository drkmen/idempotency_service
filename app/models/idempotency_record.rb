class IdempotencyRecord < ApplicationRecord
  validates :idempotency_key, presence: true, uniqueness: true
  validates :fingerprint, presence: true
  validates :response_status, presence: true
end
