# frozen_string_literal: true

require "shopify_api"
require "json"

class ShopifyClient
  attr_reader :shop_name, :token, :api_key, :api_secret, :api_version

  # client = ShopifyClient.new(shop_name: "kipcialugo", token: "fad883c9a04c6e4e9f131ca2b3f8e757", api_key: "bc870fa4b474561310a3c63f4b34cec5", api_secret: "", api_version: "2025-07")
  # client = ShopifyClient.new(shop_name: "kipcialugo", token: "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", api_key: "51710a1b8cf5b19c62f4612e453f864a", api_secret: "8589cf1463e9908534280751d9eb93b6", api_version: "2023-07")
  def initialize(shop_name: nil, token: nil, api_key: nil, api_secret: nil, api_version: nil)
    @shop_name = shop_name || ENV.fetch("SHOPIFY_SHOP_NAME", nil)
    @token = token || ENV.fetch("SHOPIFY_TOKEN", nil)
    @api_key = api_key || ENV.fetch("SHOPIFY_API", nil)
    @api_secret = api_secret || ENV.fetch("SHOPIFY_SECRET", nil)
    @api_version = api_version || ENV.fetch("SHOPIFY_VERSION", nil)
    set_shopify
  end

  def shopify_products
    session = create_session

    ShopifyAPI::Product.all(
      session:,
      ids: nil
    )
  end

  def shopify_create_product(new_product)
    session = create_session
    product = ShopifyAPI::Product.new(session:)
    product.title = new_product["title"]
    product.body_html = new_product["description"]
    product.vendor = new_product["vendor"] || "ideardev"
    product.product_type = new_product["category"]
    product.price = new_product["price"].to_f
    product.tags = [ "#{new_product['category']}, #{new_product['branch']}, " ]
    product.images = [ { "src" => new_product["image"] } ]
    product.inventory_quantity = 10
    product.old_inventory_quantity = 5
    product.quantity = 10
    product.sku = new_product["sku"]
    product.barcode = new_product["url"]

    product.variants = new_product["variants"] if new_product["variants"]
    product.options = new_product["options"] if new_product["options"]

    product.status = new_product["active"] ? "active" : "draft"
    product.save!
    product
  end

  def get_products
    session = create_session

    ShopifyAPI::Product.all(
      session:,
      limit: 250
    )
  end

  # Nueva función para crear productos con estructura completa
  def create_product_with_full_structure(product_data)
    session = create_session
    product = ShopifyAPI::Product.new(session:)

    # Configurar propiedades básicas del producto
    product.title = product_data["title"]
    product.body_html = product_data["body_html"] || product_data["description"]
    product.vendor = product_data["vendor"] || "ideardev"
    product.product_type = product_data["product_type"] || product_data["category"] || "General"

    # Manejo de estado publicado
    if product_data.key?("published")
      product.published = product_data["published"]
      product.status = product_data["published"] ? "active" : "draft"
    else
      product.published = true
      product.status = "active"
    end

    # Manejo de tags
    if product_data["tags"].is_a?(Array)
      product.tags = product_data["tags"].join(", ")
    elsif product_data["tags"].is_a?(String)
      product.tags = product_data["tags"]
    else
      product.tags = ""
    end

    # Procesar opciones del producto
    if product_data["options"]&.any?
      product.options = product_data["options"].map.with_index do |option, index|
        {
          "name" => option["name"],
          "position" => option["position"] || (index + 1),
          "values" => option["values"]
        }
      end
    end

    # Procesar variantes
    if product_data["variants"]&.any?
      product.variants = product_data["variants"].map do |variant|
        variant_data = {
          "price" => (variant["price"] || "0.00").to_f,
          "sku" => variant["sku"] || "",
          "inventory_quantity" => variant["inventory_quantity"] || 10,
          "inventory_management" => variant["inventory_management"] || "shopify",
          "taxable" => variant["taxable"].nil? ? true : variant["taxable"],
          "requires_shipping" => variant["requires_shipping"].nil? ? true : variant["requires_shipping"]
        }

        # Agregar opciones de variante
        variant_data["option1"] = variant["option1"] if variant["option1"]
        variant_data["option2"] = variant["option2"] if variant["option2"]
        variant_data["option3"] = variant["option3"] if variant["option3"]

        # Propiedades adicionales opcionales
        variant_data["weight"] = variant["weight"].to_f if variant["weight"]
        variant_data["weight_unit"] = variant["weight_unit"] if variant["weight_unit"]
        variant_data["barcode"] = variant["barcode"] if variant["barcode"]
        variant_data["compare_at_price"] = variant["compare_at_price"].to_f if variant["compare_at_price"]
        variant_data["old_inventory_quantity"] = variant["old_inventory_quantity"] || variant["inventory_quantity"] || 10
        variant_data["quantity"] = variant["quantity"] || variant["inventory_quantity"] || 10

        variant_data
      end
    end

    # Procesar imágenes
    if product_data["images"]&.any?
      product.images = product_data["images"].map do |image|
        image_data = { "src" => image["src"] }
        image_data["variant_ids"] = image["variant_ids"] if image["variant_ids"]
        image_data["alt"] = image["alt"] if image["alt"]
        image_data
      end
    elsif product_data["image"]
      product.images = [ { "src" => product_data["image"] } ]
    else
      # Imagen por defecto si no se proporciona ninguna
      product.images = []
    end

    # Configurar precio base si no hay variantes
    if product_data["price"] && (!product_data["variants"] || product_data["variants"].empty?)
      product.price = product_data["price"].to_f
    end

    # Configurar SKU base si no hay variantes
    if product_data["sku"] && (!product_data["variants"] || product_data["variants"].empty?)
      product.sku = product_data["sku"]
    end

    # Configurar campos adicionales para compatibilidad
    product.inventory_quantity = product_data["inventory_quantity"] || 10
    product.old_inventory_quantity = product_data["old_inventory_quantity"] || 5
    product.quantity = product_data["quantity"] || 10
    product.barcode = product_data["barcode"] || product_data["url"] || ""

    # Guardar el producto usando la librería Shopify
    product.save!
    product
  end

  def get_product(title)
    session = create_session

    ShopifyAPI::Product.all(
      session:,
      title:
    )
  end

  def exis_in_colection(product_id)
    session = create_session

    ShopifyAPI::Collect.all(
      session:,
      product_id:
    )
  end

  # pendiente recibir un objeto para rempalzar lo que se quiere
  def update_product(product_id, _new_product)
    session = create_session

    product = ShopifyAPI::Product.new(session:)
    product.id = product_id.to_i
    # product.body_html = new_product['body_html']
    product.save!
  end

  def get_colection(id)
    session = create_session

    ShopifyAPI::Collection.find(
      session:,
      id:
    )
  end

  def get_colects
    session = create_session

    ShopifyAPI::Collect.all(
      session:
    )
  end

  def get_colect(id)
    session = create_session

    ShopifyAPI::Collect.find(
      session:,
      id:
    )
  end

  def add_product_to_colection(product_id, collection_id)
    session = create_session

    collect = ShopifyAPI::Collect.new(session:)
    collect.product_id = product_id
    collect.collection_id = collection_id
    collect.save!
  end

  def add_custom_collections(name, products)
    session = create_session

    custom_collection = ShopifyAPI::CustomCollection.new(session:)
    custom_collection.title = name
    custom_collection.collects = products
    custom_collection.save!
  end

  def add_inventory(locale_id, inventory_item_id, count)
    session = create_session

    inventory_level = ShopifyAPI::InventoryLevel.new(session:)

    inventory_level.set(
      session:,
      body: {
        location_id: locale_id,
        inventory_item_id:,
        available: count
      }
    )
  end

  def update_custom_collections(id, products)
    session = create_session

    custom_collection = ShopifyAPI::CustomCollection.new(session:)
    custom_collection.id = id
    custom_collection.collects = products
    custom_collection.save!
  end

  def set_shopify
    ShopifyAPI::Context.setup(
      api_key: @api_key,
      api_secret_key: @api_secret,
      host_name: @shop_name,
      scope: "read_orders,read_products,etc",
      # session_storage: ShopifyAPI::Auth::FileSessionStorage.new, # This is only to be used for testing
      is_embedded: true, # Set to true if you are building an embedded app
      is_private: false, # Set to true if you are building a private app
      api_version: @api_version # The version of the API you would like to use
    )
  end

  private

  def create_session
    ShopifyAPI::Auth::Session.new(
      shop: "#{@shop_name}.myshopify.com",
      access_token: @token
    )
  end
end
