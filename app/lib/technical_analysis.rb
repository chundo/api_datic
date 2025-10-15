require "binance"
# require "yfinance"

class TechnicalAnalysis
  # Diccionario que mapea símbolos base a los formatos de cada proveedor
  SYMBOL_MAPPING = {
    "BTC" => {
      provider1: "BTCUSDT", # Para Binance (fetch_binance_historical_data)
      provider2: "BTC/USD"  # Para el otro proveedor (fetch_historical_data, fetch_current_price)
    },
    "ETH" => {
      provider1: "ETHUSDT",
      provider2: "ETH/USD"
    },
    "XRP" => {
      provider1: "XRPUSDT",
      provider2: "XRP/USD"
    }
    # Agrega más símbolos según necesites
  }.freeze


  def initialize
    # Inicializador vacío, se puede eliminar si no se necesita
  end

  # Calcula el precio de entrada como un precio de rebote confirmado
  # Ejemplo práctico: Si el precio baja de $42,000 a $41,000 y luego sube a $41,300:
  # - Stop Loss = Mínimo reciente - buffer
  #   Buffer puede ser un porcentaje (ej. 0.5% a 1%) o una cantidad fija
  #   Mínimo reciente = $41,000, Buffer = $100
  #   Stop Loss = $41,000 - $100 = $40,900
  # - Trailing Stop = Último mínimo local - buffer
  #   Alternativamente, Trailing Stop = Media Móvil (n) - buffer
  # - Relación Riesgo/Recompensa (RR) = (Precio objetivo - Precio de entrada) / (Precio de entrada - Stop Loss)
  #   Entrada = $41,300, Objetivo = $44,500, Stop Loss = $40,900
  #   RR = (44,500 - 41,300) / (41,300 - 40,900) = 3.2 (buena operación)

  # Parámetros:
  # - prices: precios (arreglo de precios históricos para identificar el rebote)
  # - target_price: precio_objetivo (precio objetivo para calcular la relación riesgo/recompensa)
  # - buffer: buffer (valor fijo o porcentaje para ajustar el stop loss y trailing stop)
  # - buffer_type: tipo_buffer (tipo de buffer: :fixed para valor fijo, :percentage para porcentaje)
  # - ma_period: periodo_media_movil (período para calcular la media móvil, usado en trailing stop alternativo)
  def self.calculate_bounce(prices: [], target_price: 0, buffer: 0, buffer_type: :fixed, ma_period: 5)
    # Validar datos de entrada
    return { error: "A non-empty array of prices is required" } if prices.empty?
    return { error: "At least 3 data points are required to detect a bounce" } if prices.size < 3
    return { error: "Target price must be a valid number" } unless target_price.is_a?(Numeric) && target_price > 0
    return { error: "Buffer must be a valid non-negative number" } unless buffer.is_a?(Numeric) && buffer >= 0
    return { error: "Buffer type must be :fixed or :percentage" } unless [ :fixed, :percentage ].include?(buffer_type)
    return { error: "Moving average period must be a positive integer" } unless ma_period.is_a?(Integer) && ma_period > 0

    # Identificar el rebote: buscar un mínimo reciente seguido de un aumento
    recent_low_index = prices.each_with_index.min_by { |price, _| price }[1]
    return { error: "Cannot confirm bounce: insufficient data after the recent low" } if recent_low_index >= prices.size - 1

    recent_low = prices[recent_low_index]
    entry_price = prices.last # Precio de entrada es el último precio (rebote confirmado)
    return { error: "No bounce detected: price did not increase after recent low" } unless entry_price > recent_low

    # Calcular el buffer ajustado según el tipo
    buffer_value = if buffer_type == :fixed
                     buffer
    else
                     recent_low * buffer # Buffer como porcentaje del mínimo reciente
    end

    # Calcular Stop Loss: Mínimo reciente - buffer
    stop_loss = recent_low - buffer_value
    return { error: "Stop loss is negative or zero, adjust buffer" } if stop_loss <= 0

    # Calcular Trailing Stop
    # Opción 1: Último mínimo local - buffer
    trailing_stop_local_low = recent_low - buffer_value

    # Opción 2: Media Móvil (n) - buffer
    ma_prices = prices.last(ma_period)
    return { error: "Not enough data points for moving average calculation" } if ma_prices.size < ma_period
    moving_average = calculate_average(prices: ma_prices)
    trailing_stop_ma = moving_average - buffer_value

    # Calcular Relación Riesgo/Recompensa (RR)
    risk = entry_price - stop_loss
    reward = target_price - entry_price
    return { error: "Cannot calculate RR: risk is zero or negative" } if risk <= 0
    return { error: "Cannot calculate RR: reward is negative" } if reward < 0
    risk_reward_ratio = (reward / risk).round(2)

    # Determinar si la operación es buena (RR >= 2 es generalmente considerado bueno)
    trade_quality = if risk_reward_ratio >= 2
                      "Good trade (RR: #{risk_reward_ratio})"
    else
                      "Risky trade (RR: #{risk_reward_ratio})"
    end

    {
      entry_price: entry_price,
      recent_low: recent_low,
      stop_loss: stop_loss.round(2),
      trailing_stop_local_low: trailing_stop_local_low.round(2),
      trailing_stop_moving_average: trailing_stop_ma.round(2),
      risk_reward_ratio: risk_reward_ratio,
      trade_quality: trade_quality
    }
  end

  # Parámetros:
  # - prices: precios (arreglo de precios históricos)
  # - current_price: precio_actual (precio actual del activo)
  # - sensitivity: sensibilidad (factor para ajustar los umbrales de ruptura)
  # - min_data_points: puntos_de_datos_mínimos (número mínimo de datos requeridos)
  def self.detect_breakout(prices: [], current_price: 0, sensitivity: 1.0, min_data_points: 5)
    # Validar datos de entrada
    return { error: "A non-empty array of prices is required" } if prices.empty?
    return { error: "At least #{min_data_points} data points are required for analysis" } if prices.size < min_data_points
    return { error: "Current price must be a valid number" } unless current_price.is_a?(Numeric)

    average_price = calculate_average(prices: prices)
    standard_deviation = calculate_standard_deviation(prices: prices)

    upper_threshold = average_price + (standard_deviation * sensitivity)
    lower_threshold = average_price - (standard_deviation * sensitivity)

    breakout_up = current_price > upper_threshold
    breakout_down = current_price < lower_threshold
    trend_up = current_price > average_price
    trend_down = current_price < average_price

    # Calcular diferencia porcentual para decisión detallada
    percentage_diff = if breakout_up
                       ((current_price - upper_threshold) / upper_threshold * 100).round(2)
    elsif breakout_down
                       ((lower_threshold - current_price) / lower_threshold * 100).round(2)
    else
                       ((current_price - average_price) / average_price * 100).round(2)
    end

    # Determinar decisión basada en ruptura o tendencia
    decision = if breakout_up
                 "Breakout to the upside detected (#{percentage_diff}% above upper threshold #{upper_threshold.round(2)}). Consider buying or taking profits."
    elsif breakout_down
                 "Breakout to the downside detected (#{percentage_diff}% below lower threshold #{lower_threshold.round(2)}). Consider selling or cutting losses."
    elsif trend_up
                 "Uptrend detected (#{percentage_diff}% above average). Hold position."
    else
                 "Downtrend detected (#{-percentage_diff}% below average). Watch closely."
    end

    {
      average_price: average_price.round(2),
      standard_deviation: standard_deviation.round(2),
      upper_threshold: upper_threshold.round(2),
      lower_threshold: lower_threshold.round(2),
      breakout_up: breakout_up,
      breakout_down: breakout_down,
      trend_up: trend_up,
      trend_down: trend_down,
      percentage_difference: percentage_diff,
      decision: decision
    }
  end


  # Parámetros:
  # - symbol: símbolo (símbolo del par de trading, ej. BTCUSDT)
  # - limit: límite (número de registros históricos a obtener)
  # - interval: intervalo (intervalo de tiempo, ej. 15m)
  def self.analyze_market(symbol: "BTCUSDT", limit: 20, interval: "15m")
    mapped_symbol1 = SYMBOL_MAPPING.dig(symbol, :provider1) || symbol
    mapped_symbol2 = SYMBOL_MAPPING.dig(symbol, :provider2) || symbol

    historical_data = fetch_historical_data(symbol: mapped_symbol2, limit: limit, interval: "15min")
    current_data = fetch_current_price(symbol: mapped_symbol2)
    binance_historical_data = fetch_binance_historical_data(symbol: mapped_symbol1, limit: limit, interval: interval)

    historical_closes = historical_data.map { |entry| entry["close"].to_f }
    previous_price = historical_closes.first

    current_price = current_data.dig("price", "price").to_f
    current_volume = current_data.dig("price", "volume").to_f
    average_volume = binance_historical_data.first&.dig(5).to_f || 0

    signal = generate_trading_signal(
      previous_price: previous_price,
      current_price: current_price,
      current_volume: current_volume,
      average_volume: average_volume
    )
    breakout_analysis = detect_breakout(prices: historical_closes, current_price: current_price)

    {
      symbol: symbol,
      previous_price: previous_price,
      previous_volume: current_volume,
      current_price: current_price,
      average_volume: average_volume,
      signal: signal,
      breakout_analysis: breakout_analysis
    }
  end

  # Parámetros:
  # - prices: precios (arreglo de precios históricos)
  # calcula la media mobil
  def self.calculate_average(prices: [])
    # Evitar división por cero
    return 0 if prices.empty?
    prices.sum.to_f / prices.size
  end

  # Parámetros:
  # - prices: precios (arreglo de precios históricos)
  def self.calculate_standard_deviation(prices: [])
    # Evitar división por cero
    return 0 if prices.empty?
    average = calculate_average(prices: prices)
    variance = prices.sum { |price| (price - average) ** 2 } / prices.size
    Math.sqrt(variance)
  end

  # Parámetros:
  # - symbol: símbolo (símbolo del par de trading, ej. BTC/USD)
  # - limit: límite (número de registros históricos a obtener)
  # - interval: intervalo (intervalo de tiempo, ej. 15min)
  def self.fetch_historical_data(symbol: "BTC/USD", limit: 20, interval: "15min")
    mapped_symbol = SYMBOL_MAPPING.dig(symbol, :provider2) || symbol
    FinanceServices.get_data("#{Settings.technical_anality.provider2}/api/historical?symbol=#{mapped_symbol}&limit=#{limit}&interval=#{interval}")
    # https://api.binance.com/api/v3/klines?symbol=BTCUSDT&limit=20&interval=15m #volumen 5 (6)
    # values = data.map { |entry| entry["close"] }
  end

  # Parámetros:
  # - symbol: símbolo (símbolo del par de trading, ej. BTCUSDT)
  # - limit: límite (número de registros históricos a obtener)
  # - interval: intervalo (intervalo de tiempo, ej. 15m)
  def self.fetch_binance_historical_data(symbol: "BTCUSDT", limit: 20, interval: "15m")
    mapped_symbol = SYMBOL_MAPPING.dig(symbol, :provider1) || symbol
    FinanceServices.get_data("#{Settings.technical_anality.provider1}/api/v3/klines?symbol=#{mapped_symbol}&interval=#{interval}&limit=#{limit}")
  end

  # Parámetros:
  # - symbol: símbolo (símbolo del par de trading, ej. BTC/USD)
  def self.fetch_current_price(symbol: "BTC/USD")
    mapped_symbol = SYMBOL_MAPPING.dig(symbol, :provider2) || symbol
    data = FinanceServices.get_data("#{Settings.technical_anality.provider2}/api/comprehensive?symbol=#{mapped_symbol}")
    data
  end

  # Parámetros:
  # - previous_price: precio_anterior (precio anterior del activo)
  # - current_price: precio_actual (precio actual del activo)
  # - current_volume: volumen_actual (volumen actual de trading)
  # - average_volume: promedio_volumen (volumen promedio de trading)
  def self.generate_trading_signal(previous_price: 8.70, current_price: 8.95, current_volume: 1200, average_volume: 1000)
    # Validar datos de entrada
    return "Signal: WAIT (invalid data)" unless [ previous_price, current_price, current_volume, average_volume ].all? { |v| v.is_a?(Numeric) && v >= 0 }

    if current_price > previous_price && current_volume > average_volume
      "Signal: BUY (strong upward trend with high participation)"
    elsif current_price < previous_price && current_volume > average_volume
      "Signal: SELL (strong downward pressure with high participation)"
    else
      "Signal: WAIT (no clear confirmation)"
    end
  end

  # Parámetros:
  # - symbol: símbolo (símbolo del par de trading, ej. BTCUSDT)
  def self.fetch_binance_ticker(symbol: "BTCUSDT")
    key = ENV["API_KY_BN"]
    secret = ENV["API_SECRET_BN"]
    client = Binance::Spot.new(key: key, secret: secret)
    mapped_symbol = SYMBOL_MAPPING.dig(symbol, :provider1) || symbol

    client.ticker_24hr(symbol: mapped_symbol)
  end

  # Parámetros:
  # - eps: eps (ganancias por acción)
  # - industry_per: per_industria (relación precio/ganancias promedio de la industria)
  # - bvps: bvps (valor contable por acción)
  # - industry_pb: pb_industria (relación precio/valor contable promedio de la industria)
  # - per_weight: peso_per (peso asignado al cálculo basado en PER)
  # - pb_weight: peso_pb (peso asignado al cálculo basado en P/B)
  def self.calculate_intrinsic_value(eps: 5, industry_per: 18, bvps: 20, industry_pb: 2, per_weight: 0.6, pb_weight: 0.4)
    value_by_per = eps * industry_per
    value_by_pb = bvps * industry_pb
    intrinsic_value = (value_by_per * per_weight) + (value_by_pb * pb_weight)
    intrinsic_value.round(2)
  end

  # Parámetros:
  # - current_price: precio_actual (precio actual del activo)
  # - intrinsic_value: valor_intrinseco (valor intrínseco estimado del activo)
  # - margin_of_safety: margen_seguridad (margen de seguridad para considerar infravaloración)
  def self.is_undervalued?(current_price: 80, intrinsic_value: 110, margin_of_safety: 0.20)
    difference = intrinsic_value - current_price
    percentage_difference = difference / intrinsic_value.to_f

    if percentage_difference >= margin_of_safety
      puts "The asset is undervalued (#{ (percentage_difference * 100).round(2) }% below intrinsic value). Buy."
      true
    elsif percentage_difference <= -margin_of_safety
      overvalued_percentage = (current_price - intrinsic_value) / intrinsic_value.to_f
      puts "The asset is overvalued (#{ (overvalued_percentage * 100).round(2) }% above intrinsic value). Sell or wait."
      false
    else
      puts "The asset is neither undervalued nor overvalued (difference: #{ (percentage_difference * 100).round(2) }%). Hold."
      false
    end
  end
end
