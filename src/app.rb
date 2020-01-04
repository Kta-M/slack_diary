require 'json'
require 'uri'
require 'date'
require 'aws-sdk-s3'

S3_DATE_FORMAT = '%Y/%m/%d.txt'
DISPLAY_DATE_FORMAT = '%Y-%m-%d(%a)'

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
def write(event:, context:)
  params = decode_body_params(event['body'])

  key_name = params.dig(:text, :date).strftime(S3_DATE_FORMAT)
  body = params.dig(:text, :body)

  s3 = Aws::S3::Resource.new
  bucket = s3.bucket(ENV['BUCKET_NAME'])
  bucket.put_object(key: key_name, body: body)

  date = params.dig(:text, :date).strftime(DISPLAY_DATE_FORMAT)

  response(
    'Success to write!',
    :success,
    [{title: date, value: body}]
  )

rescue => e
  response(
    'Failed to write.',
    :fail,
    [
      {title: 'message', value: e.message},
      {title: 'params',  value: URI.decode_www_form(event['body'].to_s).to_h['text']}
    ]
  )
end

#------------------------------------------------------------------------------
def read(event:, context:)
  params = decode_query_string_params(event['queryStringParameters'])

  key_name = params[:text].strftime(S3_DATE_FORMAT)
  s3 = Aws::S3::Resource.new
  bucket = s3.bucket(ENV['BUCKET_NAME'])
  body = bucket.object(key_name).get.body.read

  date = params[:text].strftime(DISPLAY_DATE_FORMAT)

  response(
    'Success to read!',
    :success,
    [{title: date, value: body}]
  )

rescue => e
  response(
    'Failed to read.',
    :fail,
    [
      {title: 'message', value: e.message},
      {title: 'params',  value: event.dig('multiValueQueryStringParameters', 'text')&.first}
    ]
  )
end

#------------------------------------------------------------------------------
def remind(event:, context:)
  today = Date.today

  s3 = Aws::S3::Resource.new
  bucket = s3.bucket(ENV['BUCKET_NAME'])

  fields = 10.downto(1).map do |y|
    date = today.prev_year(y)
    key_name = date.strftime(S3_DATE_FORMAT)
    if bucket.object(key_name).exists?
      body = bucket.object(key_name).get.body.read
      {title: date.strftime(DISPLAY_DATE_FORMAT), value: body}
    else
      nil
    end
  end
  fields.compact!

  uri = URI.parse(ENV['INCOMING_WEBHOOK_URL'])
  payload = slack_payload('<!channel> Write Diary!:muscle:', ':info', fields)
  Net::HTTP.post_form(uri, { payload: payload })
end

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

private

def valid_token?(token)
  token == ENV['SLASH_COMMAND_TOKEN']
end
def valid_channel?(channel)
  channel == ENV['VALID_CHANNEL_ID']
end
def valid_user?(user)
  user == ENV['VALID_USER_ID']
end

def validate_params!(params)
  raise 'invalid_token'   unless valid_token?(params[:token])
  raise 'invalid_channel' unless valid_channel?(params[:channel_id])
  raise 'invalid_user'    unless valid_user?(params[:user_id])
end

#------------------------------------------------------------------------------
def decode_body_params(body)
  raise 'invalid_event' if body.nil?

  # リクエストボディをデコード
  params = URI.decode_www_form(body).map{|s| [s.first.to_sym, s.last]}.to_h

  # パラメーターのバリデーション
  validate_params!(params)

  # メッセージから日付と内容を取得
  m = /\A(?<date>\d{2,4}-\d{1,2}-\d{1,2})(?<body>[\s\S]*)\z/.match(params[:text])
  raise 'invalid_message' if m.nil?
  text_params = {
    date: Date.parse(m['date']),
    body: m['body'].strip
  }
  params[:text] = text_params

  params
end

#------------------------------------------------------------------------------
def decode_query_string_params(query_string_hash)
  raise 'invalid_event' if query_string_hash.nil?

  # パラメーターのキーをシンボルに
  params = query_string_hash.each_with_object({}) do |(k, v), ret|
    ret[k.to_sym] = v
  end

  # パラメーターのバリデーション
  validate_params!(params)

  # 与えられた日付をDateオブジェクトに
  params[:text] = Date.parse(params[:text])

  params
end

#------------------------------------------------------------------------------
def response(pretext, color_type, fields)
  {
    statusCode: 200,
    body: slack_payload(pretext, color_type, fields)
  }
end

def slack_payload(pretext, color_type, fields)
  color = {
    info:    "#eeeeee",
    success: "#36a64f",
    fail:    "#D00000"
  }

  {
    attachments: [{
      pretext: pretext,
      color: color[color_type],
      fields: fields
    }]
  }.to_json
end

#------------------------------------------------------------------------------
def post_message_to_slack(url, payload)
  uri = URI.parse(url)
  Net::HTTP.post_form(uri, { payload: payload })
end
