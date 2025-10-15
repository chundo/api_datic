## Crear producto en Shopify

Este servicio permite crear un producto en una tienda Shopify mediante una solicitud HTTP POST.

### Endpoint

`POST /api/v1/shopify/create_product`

### Parámetros (JSON en el body)

- **auth**: Objeto con las credenciales de la tienda Shopify
  - `shop_name`: Nombre de la tienda (sin `.myshopify.com`)
  - `token`: Token de acceso privado
  - `api_key`: API Key de la app
  - `api_secret`: API Secret de la app
  - `api_version`: Versión de la API de Shopify (ej: "2023-07")
- **product**: Objeto con los datos del producto
  - `title`: Nombre del producto
  - `description`: Descripción HTML o texto
  - `category`: Categoría o tipo de producto
  - `price`: Precio base
  - `branch`: Sucursal o rama (opcional, para tags)
  - `image`: URL de la imagen principal
  - `sku`: SKU principal
  - `url`: Código de barras o identificador externo
  - `vendor`: Proveedor (opcional, por defecto "ideardev")
  - `active`: true/false para publicar o dejar en borrador
  - `variants`: Array de variantes (cada una puede tener: option1, price, sku, barcode, taxable, requires_shipping, inventory_quantity, inventory_management)

### Ejemplo de request

```json
{
  "auth": {
    "shop_name": "ideardev",
    "token": "string",
    "api_key": "string",
    "api_secret": "string",
    "api_version": "2023-07"
  },
  "product": {
    "title": "Camiseta",
    "description": "Camiseta de algodón",
    "category": "Ropa",
    "price": 25.99,
    "branch": "Sucursal 1",
    "image": "https://ejemplo.com/camiseta.jpg",
    "sku": "CAMI-001",
    "url": "https://ejemplo.com/barcode",
    "vendor": "MiProveedor",
    "active": true,
    "variants": [
      {
        "option1": "Rojo",
        "price": 25.99,
        "sku": "CAMI-001-ROJO",
        "barcode": "1234567890",
        "taxable": true,
        "requires_shipping": true,
        "inventory_quantity": 10,
        "inventory_management": "shopify"
      },
      {
        "option1": "Azul",
        "price": 25.99,
        "sku": "CAMI-001-AZUL",
        "barcode": "0987654321",
        "taxable": true,
        "requires_shipping": true,
        "inventory_quantity": 8,
        "inventory_management": "shopify"
      }
    ]
  }
}
```

### Ejemplo de respuesta exitosa

```json
{
  "success": true,
  "product": {
    "id": 123456789,
    "title": "Camiseta",
    ...
  }
}
```

Si ocurre un error:

```json
{
  "success": false,
  "error": "Mensaje de error"
}
```
# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

- Ruby version

- System dependencies

- Configuration

- Database creation

- Database initialization

- How to run the test suite

- Services (job queues, cache servers, search engines, etc.)

- Deployment instructions

- ...

https://github.com/yjacquin/fast-mcp
https://github.com/funwarioisii/mcp-rb

movie = FFMPEG::Movie.new("reu.mp4")
movie = FFMPEG::Movie.new("output.mov")
movie = FFMPEG::Movie.new("fernando.wav")

movie.screenshot("screenshot.jpg")

## Toma una captura de pantalla a los 5 segundos

movie.screenshot("screenshot.bmp", seek_time: 5, resolution: '320x240')

## Transcodifica el video a otro formato con una marca de agua

options = {
watermark: "public/logo2.png", resolution: "640x360",
watermark_filter: { position: "RT", padding_x: 10, padding_y: 10 }
}
movie.transcode("output.mov", options)

## Toma 20 capturas de pantalla a 1/6 de la velocidad original

movie.screenshot("screenshot\_%d.jpg", { vframes: 20, frame_rate: '1/6' }, validate: false)

## Transcodifica el video a otro formato con un callback de progreso

movie.transcode("reu.mp4") { |progress| puts progress }

movie.transcode("output1.mp4", %w(-ss 00:00:00 -t 00:25:00 ))


## Generar documentacion

{
  "auth": {
    "shop_name": "kipcialugo",
    "token": "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",
    "api_key": "51710a1b8cf5b19c62f4612e453f864a",
    "api_secret": "8589cf1463e9908534280751d9eb93b6",
    "api_version": "2023-07"
  },
  "product": {
    "title": "Camiseta",
    "description": "Camiseta de algodón",
    "category": "Ropa",
    "price": 25.99,
    "branch": "Sucursal 1",
    "image": "https://ejemplo.com/camiseta.jpg",
    "sku": "CAMI-001",
    "url": "https://ejemplo.com/barcode",
    "vendor": "MiProveedor",
    "active": true,
    "variants": [
      {
        "option1": "Rojo",
        "price": 25.99,
        "sku": "CAMI-001-ROJO",
        "barcode": "1234567890",
        "taxable": true,
        "requires_shipping": true,
        "inventory_quantity": 10,
        "inventory_management": "shopify"
      },
      {
        "option1": "Azul",
        "price": 25.99,
        "sku": "CAMI-001-AZUL",
        "barcode": "0987654321",
        "taxable": true,
        "requires_shipping": true,
        "inventory_quantity": 8,
        "inventory_management": "shopify"
      }
    ]
  }
}