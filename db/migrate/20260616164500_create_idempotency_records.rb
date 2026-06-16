class CreateIdempotencyRecords < ActiveRecord::Migration[7.0]
  def change
    create_table :idempotency_records, id: :uuid do |t|
      t.string :idempotency_key, null: false
      t.string :fingerprint, null: false
      t.jsonb :response_body
      t.integer :response_status
      t.datetime :expires_at, index: true
      t.timestamps
    end
    add_index :idempotency_records, :idempotency_key, unique: true
  end
end
