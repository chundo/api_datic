
require "set"

module Api
  module V1
    class ShopifyController < ApplicationController
        # POST /api/v1/shopify/create_product
        def create_product
            # Recibe los datos de autenticación por parámetros
            auth_params = params.require(:auth).permit(:shop_name, :token, :api_key, :api_secret, :api_version)
            client = ShopifyClient.new(
                shop_name: auth_params[:shop_name],
                token: auth_params[:token],
                api_key: auth_params[:api_key],
                api_secret: auth_params[:api_secret],
                api_version: auth_params[:api_version]
            )

            # Permitir parámetros completos para la nueva estructura
            permitted_options = [ :name, :position, values: [] ]
            permitted_variants = [ :option1, :option2, :option3, :price, :sku, :barcode, :taxable, :requires_shipping,
                                 :inventory_quantity, :inventory_management, :weight, :weight_unit, :compare_at_price ]
            permitted_images = [ :src, :alt, variant_ids: [] ]

            product_params = params.require(:product).permit(
                :title, :body_html, :description, :vendor, :product_type, :category, :published, :price,
                :branch, :image, :sku, :url, :active, :inventory_quantity, :old_inventory_quantity, :quantity,
                :sku,
                tags: [],
                options: permitted_options,
                variants: permitted_variants,
                images: permitted_images
            )

            # Convertir a hash con claves string
            product_hash = product_params.to_h.deep_transform_keys(&:to_s)

            # Procesar variants si existe
            if product_hash["variants"].present? && product_hash["variants"].is_a?(Array)
                product_hash["variants"] = product_hash["variants"].map do |variant|
                    variant.is_a?(ActionController::Parameters) ? variant.to_h.transform_keys(&:to_s) : variant
                end
            end

            # Procesar options si existe
            if product_hash["options"].present? && product_hash["options"].is_a?(Array)
                product_hash["options"] = product_hash["options"].map do |option|
                    option.is_a?(ActionController::Parameters) ? option.to_h.transform_keys(&:to_s) : option
                end
            end

            # Procesar images si existe
            if product_hash["images"].present? && product_hash["images"].is_a?(Array)
                product_hash["images"] = product_hash["images"].map do |image|
                    image.is_a?(ActionController::Parameters) ? image.to_h.transform_keys(&:to_s) : image
                end
            end

            # Manejo de backward compatibility para campos legacy
            product_hash["body_html"] = product_hash["body_html"] || product_hash["description"]
            product_hash["product_type"] = product_hash["product_type"] || product_hash["category"]
            product_hash["vendor"] = product_hash["vendor"].presence || "ideardev"

            # active/published debe ser booleano
            if product_hash.key?("published")
                product_hash["published"] = product_hash["published"].to_s == "true"
            elsif product_hash.key?("active")
                product_hash["published"] = product_hash["active"].to_s == "true"
            else
                product_hash["published"] = true
            end

            begin
                # Usar la nueva función que maneja estructura completa
                product = client.create_product_with_full_structure(product_hash)
                render json: { success: true, product: product }, status: :created
            rescue => e
                render json: { success: false, error: e.message }, status: :unprocessable_entity
            end
        end

        # POST /api/v1/shopify/migrar_productos
        def migrar_productos
            # Recibe los datos de autenticación - permite tanto formato anidado como plano
            if params[:auth].present?
                # Formato anidado: auth[shop_name], auth[token], etc.
                auth_params = params.require(:auth).permit(:shop_name, :token, :api_key, :api_secret, :api_version)
                client = ShopifyClient.new(
                    shop_name: auth_params[:shop_name],
                    token: auth_params[:token],
                    api_key: auth_params[:api_key],
                    api_secret: auth_params[:api_secret],
                    api_version: auth_params[:api_version]
                )
            else
                # Formato plano: shop_name, token, api_key, etc.
                auth_params = params.permit(:shop_name, :token, :api_key, :api_secret, :api_version)
                client = ShopifyClient.new(
                    shop_name: auth_params[:shop_name],
                    token: auth_params[:token],
                    api_key: auth_params[:api_key],
                    api_secret: auth_params[:api_secret],
                    api_version: auth_params[:api_version]
                )
            end

            # Verificar que se haya enviado un archivo
            unless params[:file].present?
                return render json: { success: false, error: "Debe proporcionar un archivo para migrar" }, status: :bad_request
            end

            begin
                # Procesar el archivo usando ConvertTo.csv_json
                file = params[:file]
                data = ConvertTo.csv_json(file)
                products_array = JSON.parse(data[:json_data])

                results = []
                successful_migrations = 0
                failed_migrations = 0

                products_array.each_with_index do |product, index|
                    begin
                        # Transformar el producto de kipcia al formato de Shopify
                        shopify_product = transform_kipcia_to_shopify(product)

                        # Debug: log del producto transformado (solo para desarrollo)
                        Rails.logger.info "Producto transformado: #{shopify_product.to_json}" if Rails.env.development?

                        # Crear el producto en Shopify usando la nueva función con estructura completa
                        created_product = client.create_product_with_full_structure(shopify_product)

                        results << {
                            index: index,
                            sku: product["SKU"],
                            name: product["NOMBRE"],
                            status: "success",
                            product: product,
                            product2: shopify_product,
                            shopify_product_id: created_product.id,
                            shopify_product: {
                                id: created_product.id,
                                title: created_product.title,
                                handle: created_product.handle
                            }
                        }
                        successful_migrations += 1

                    rescue => product_error
                        results << {
                            index: index,
                            sku: product["SKU"],
                            name: product["NOMBRE"],
                            status: "error",
                            product: product,
                            product2: shopify_product,
                            error: product_error.message
                        }
                        failed_migrations += 1
                    end
                end

                render json: {
                    success: true,
                    message: "Migración completada",
                    summary: {
                        total_products: products_array.length,
                        successful: successful_migrations,
                        failed: failed_migrations
                    },
                    results: results
                }, status: :ok

            rescue => e
                render json: { success: false, error: "Error procesando el archivo: #{e.message}" }, status: :unprocessable_entity
            end
        end

        private

        # Transforma un producto de formato kipcia al formato Shopify
        def transform_kipcia_to_shopify(product)
            # Configurar las opciones del producto dinámicamente basándose en las cabeceras
            options = []

            # Verificar si existe la cabecera COLORES y tiene valores
            if product.key?("COLORES") && product["COLORES"].present?
                colors = extract_options(product["COLORES"])
                if colors.any?
                    options << {
                        "name" => "Color",
                        "position" => 1,
                        "values" => colors
                    }
                end
            end

            # Verificar si existe la cabecera TALLAS y tiene valores
            if product.key?("TALLAS") && product["TALLAS"].present?
                sizes = extract_options(product["TALLAS"])
                if sizes.any?
                    position = options.length + 1
                    options << {
                        "name" => "Talla",
                        "position" => position,
                        "values" => sizes
                    }
                end
            end

            # Construir variantes con títulos dinámicos
            variants = build_variants(product)

            {
                "title" => product["NOMBRE"],
                "body_html" => product["description"] || product["DESCRIPCION"] || "<p>Producto migrado desde Kipcia</p>",
                "product_type" => product["CATEGORIA"] || "General",
                "price" => extract_price(product["PRECIO"]),
                "image" => product["IMAGEN"] || product["LINK"],
                "sku" => product["SKU"],
                "published" => false, # Siempre como draft inicialmente
                "vendor" => product["PROVEEDOR"] || "ideardev",
                "variants" => variants,
                "options" => options,
                "tags" => [product["CATEGORIA"], product["PROVEEDOR"]].compact.reject(&:blank?),
                "barcode" => product["LINK"] || "",
                "inventory_quantity" => 10
            }
        end

        # Extrae el precio del producto, manejando diferentes formatos
        def extract_price(price_string)
            return 0.0 if price_string.blank?

            # Remover símbolos de moneda y espacios, convertir comas a puntos
            clean_price = price_string.to_s.gsub(/[$,\s]/, "").gsub(",", ".")
            clean_price.to_f
        end

        # Extrae opciones de un string separado por comas o similar
        def extract_options(options_string)
            return [] if options_string.blank?

            # Dividir por comas, limpiar espacios y capitalizar apropiadamente
            options_string.split(/[,;|]/)
                          .map(&:strip)
                          .reject(&:blank?)
                          .map { |option| option.split.map(&:capitalize).join(" ") }
                          .uniq
        end

        # Construye las variantes basándose en los datos de kipcia
        def build_variants(product)
            variants = []
            variant_combinations = Set.new # Para evitar duplicados

            # Extraer y limpiar colores y tallas
            colors = extract_options(product["COLORES"]).map(&:strip).reject(&:blank?).uniq
            sizes = extract_options(product["TALLAS"]).map(&:strip).reject(&:blank?).uniq

            base_price = extract_price(product["PRECIO"])
            base_sku = product["SKU"]

            if colors.any? && sizes.any?
                # Crear variantes para cada combinación de color y talla
                colors.each do |color|
                    sizes.each do |size|
                        combination_key = "#{color.upcase}-#{size.upcase}"

                        unless variant_combinations.include?(combination_key)
                            variant_combinations.add(combination_key)

                            variants << {
                                "option1" => color.capitalize,
                                "option2" => size.upcase,
                                "price" => base_price,
                                "sku" => generate_unique_sku(base_sku, color, size),
                                "inventory_quantity" => 10,
                                "inventory_management" => "shopify",
                                "taxable" => false,
                                "requires_shipping" => true,
                                "barcode" => product["LINK"] || "",
                                "weight" => 0.5,
                                "weight_unit" => "kg"
                            }
                        end
                    end
                end
            elsif colors.any?
                # Solo colores
                colors.each do |color|
                    color_key = color.upcase

                    unless variant_combinations.include?(color_key)
                        variant_combinations.add(color_key)

                        variants << {
                            "option1" => color.capitalize,
                            "price" => base_price,
                            "sku" => generate_unique_sku(base_sku, color),
                            "inventory_quantity" => 10,
                            "inventory_management" => "shopify",
                            "taxable" => false,
                            "requires_shipping" => true,
                            "barcode" => product["LINK"] || "",
                            "weight" => 0.5,
                            "weight_unit" => "kg"
                        }
                    end
                end
            elsif sizes.any?
                # Solo tallas
                sizes.each do |size|
                    size_key = size.upcase

                    unless variant_combinations.include?(size_key)
                        variant_combinations.add(size_key)

                        variants << {
                            "option1" => size.upcase,
                            "price" => base_price,
                            "sku" => generate_unique_sku(base_sku, size),
                            "inventory_quantity" => 10,
                            "inventory_management" => "shopify",
                            "taxable" => false,
                            "requires_shipping" => true,
                            "barcode" => product["LINK"] || "",
                            "weight" => 0.5,
                            "weight_unit" => "kg"
                        }
                    end
                end
            else
                # Variante por defecto si no hay opciones específicas
                variants << {
                    "option1" => "Default",
                    "price" => base_price,
                    "sku" => base_sku,
                    "inventory_quantity" => 10,
                    "inventory_management" => "shopify",
                    "taxable" => false,
                    "requires_shipping" => true,
                    "barcode" => product["LINK"] || "",
                    "weight" => 0.5,
                    "weight_unit" => "kg"
                }
            end

            variants
        end

        # Genera un SKU único para las variantes
        def generate_unique_sku(base_sku, *options)
            return base_sku if options.empty? || options.all?(&:blank?)

            # Limpiar y formatear las opciones
            clean_options = options.compact.map do |option|
                option.to_s.strip.downcase.gsub(/[^a-z0-9]/, "")
            end.reject(&:blank?)

            return base_sku if clean_options.empty?

            "#{base_sku}-#{clean_options.join('-')}"
        end
    end
  end
end
