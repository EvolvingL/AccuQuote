-- AccuQuote pricing database — see PricingIntegration-TechnicalPlan.md §1.2
CREATE TABLE products (
  id TEXT PRIMARY KEY,              -- supplier:ean or supplier:product_id, stable across refreshes
  supplier TEXT NOT NULL,           -- 'travisperkins' | 'toolstation' | 'wickes' | 'bq_tradepoint' | 'screwfix'
  name TEXT NOT NULL,
  category TEXT,                    -- Awin feed's merchant_category, used for coarse filtering
  ean TEXT,
  mpn TEXT,
  price_pence INTEGER NOT NULL,     -- VAT-inclusive, from Awin `search_price` field, stored as integer pence
  in_stock INTEGER NOT NULL,        -- 0/1
  stock_quantity INTEGER,
  deep_link TEXT NOT NULL,          -- Awin affiliate link — also the revenue mechanism
  last_updated TEXT NOT NULL        -- ISO8601, from Awin feed's last_updated
);

CREATE INDEX idx_products_supplier_category ON products(supplier, category);
CREATE INDEX idx_products_name ON products(name);
