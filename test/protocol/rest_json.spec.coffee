helpers = require('../helpers'); AWS = helpers.AWS
Operation = AWS.Model.Operation
Buffer = helpers.util.Buffer

svc = AWS.Protocol.RestJson
describe 'AWS.Protocol.RestJson', ->

  MockJSONRESTService = helpers.util.inherit AWS.Service,
    endpointPrefix: 'mockservice'

  operation = null
  request = null
  response = null
  service = null

  beforeEach ->
    MockJSONRESTService.prototype.api = new AWS.Model.Api
      operations:
        sampleOperation:
          http:
            method: 'POST'
            uri: '/'
          input:
            type: 'structure'
            members: {}
          output:
            type: 'structure'
            members:
              a: type: 'string'
              b: type: 'string'
      shapes:
        structureshape:
          type: 'structure'
          members:
            a: type: 'string'
            b: type: 'string'

    AWS.Service.defineMethods(MockJSONRESTService)

    operation = MockJSONRESTService.prototype.api.operations.sampleOperation
    service = new MockJSONRESTService(region: 'region')
    request = new AWS.Request(service, 'sampleOperation')
    response = new AWS.Response(request)

  defop = (op) ->
    helpers.util.property(service.api.operations, 'sampleOperation',
      new Operation('sampleOperation', op, api: service.api))

  describe 'buildRequest', ->
    build = -> svc.buildRequest(request); request

    describe 'method', ->
      it 'populates method from the operation', ->
        defop http: method: 'GET'
        expect(build().httpRequest.method).to.equal('GET')

    describe 'uri', ->
      it 'populates uri from the operation', ->
        defop http: requestUri: '/path'
        expect(build().httpRequest.path).to.equal('/path')

      it 'replaces param placeholders', ->
        request.params = Id: 'abc'
        defop
          http: requestUri: '/Owner/{Id}'
          input: type: 'structure', members: Id: location: 'uri'
        expect(build().httpRequest.path).to.equal('/Owner/abc')

      it 'can replace multiple path placeholders', ->
        request.params = Id: 'abc', Count: 123
        defop
          http: requestUri: '/{Id}/{Count}'
          input:
            type: 'structure'
            members:
              Id:
                location: 'uri'
                type: 'string'
              Count:
                type: 'integer'
                location: 'uri'
        expect(build().httpRequest.path).to.equal('/abc/123')

      it 'performs querystring param replacements', ->
        request.params = Id: 'abc'
        defop
          http: requestUri: '/path'
          input:
            type: 'structure'
            members:
              Id:
                location: 'querystring'
                locationName: 'id-param'
        expect(build().httpRequest.path).to.equal('/path?id-param=abc')

    describe 'headers', ->
      it 'populates the headers with present params', ->
        request.params = ACL: 'public-read'
        defop input:
          members:
            ACL:
              location: 'header'
              locationName: 'x-amz-acl'
        expect(build().httpRequest.headers['x-amz-acl']).to.equal('public-read')

      it 'uses default rule name if .n property is not present', ->
        request.params = ACL: 'public-read'
        defop input:
          members:
            ACL:
              location: 'header'
        expect(build().httpRequest.headers['ACL']).to.equal('public-read')

      it 'works with map types', ->
        request.params =
          Metadata:
            foo: 'bar'
            abc: 'xyz'
        defop input:
          members:
            Metadata:
              type: 'map'
              location: 'headers'
              locationName: 'x-amz-meta-'

        build()
        expect(request.httpRequest.headers['x-amz-meta-foo']).to.equal('bar')
        expect(request.httpRequest.headers['x-amz-meta-abc']).to.equal('xyz')

    describe 'body', ->
      ['GET', 'HEAD'].forEach (method) ->
        it 'does not populate a body on a ' + method + ' request', ->
          request.params = Data: 'abc'
          defop
            http: method: method
            input:
              payload: 'Data'
              members:
                Data:
                  type: 'string'
          expect(build().httpRequest.body).to.equal('')

      it 'builds root element if rules contains root', ->
        request.params =
          Config:
            Name: 'foo'
            Type: 'bar'
        defop input:
          payload: 'Config'
          members:
            Config:
              type: 'structure'
              members:
                Name: type: 'string'
                Type: type: 'string'
        expect(build().httpRequest.body.toString()).to.equal(
          '{"Name":"foo","Type":"bar"}')

      it 'builds payload element as non JSON data if rules contains payload', ->
        request.params = Body: 'foobar'
        defop input:
          payload: 'Body'
          members:
            Body:
              type: 'binary'
        expect(build().httpRequest.body).to.equal('foobar')

  describe 'extractError', ->
    extractError = (body) ->
      response.httpResponse.statusCode = 500
      response.httpResponse.body = new Buffer(body)
      svc.extractError(response)

    it 'removes prefixes from the error code', ->
      extractError '{"__type":"com.amazon.coral.service#ErrorCode" }'
      expect(response.error ).to.be.instanceOf(Error)
      expect(response.error.code).to.equal('ErrorCode')
      expect(response.data).to.equal(null)

    it 'returns the full code when a # is not present', ->
      extractError '{"__type":"ErrorCode" }'
      expect(response.error ).to.be.instanceOf(Error)
      expect(response.error.code).to.equal('ErrorCode')
      expect(response.data).to.equal(null)

    it 'returns the status code when the body is blank', ->
      extractError ''
      expect(response.error ).to.be.instanceOf(Error)
      expect(response.error.code).to.equal('UnknownError')
      expect(response.error.statusCode).to.equal(500)
      expect(response.error.message).to.equal('500')
      expect(response.data).to.equal(null)

    it 'returns null for the message when not present', ->
      extractError '{"__type":"ErrorCode" }'
      expect(response.error ).to.be.instanceOf(Error)
      expect(response.error.message).to.equal(null)
      expect(response.data).to.equal(null)

    it 'returns the message when present', ->
      extractError '{"__type":"ErrorCode", "message":"Error Message" }'
      expect(response.error ).to.be.instanceOf(Error)
      expect(response.error.message).to.equal('Error Message')
      expect(response.data).to.equal(null)

    # DynamoDB and SWF return error message properties with different case
    it 'returns the message when the message property is upper-cased', ->
      extractError '{"__type":"ErrorCode", "Message":"Error Message" }'
      expect(response.error ).to.be.instanceOf(Error)
      expect(response.error.message).to.equal('Error Message')
      expect(response.data).to.equal(null)

    it 'returns a special message for RequestEntityToLarge errors', ->
      extractError '{"__type":"RequestEntityTooLarge" }'
      expect(response.error ).to.be.instanceOf(Error)
      expect(response.error.message).to.equal('Request body must be less than 1 MB')
      expect(response.data).to.equal(null)

  describe 'extractData', ->
    extractData = (body) ->
      response.httpResponse.statusCode = 200
      response.httpResponse.body = new Buffer(body)
      svc.extractData(response)

    it 'JSON parses http response bodies', ->
      extractData '{"a":1, "b":"xyz"}'
      expect(response.error).to.equal(null)
      expect(response.data).to.eql({a:1, b:'xyz'})

    it 'pulls header data out of response', ->
      response.httpResponse.headers['x-title'] = 'The title'
      defop output:
        type: 'structure'
        members:
          Title:
            location: 'header'
            locationName: 'x-title'

      extractData '{}'
      expect(response.error).to.equal(null)
      expect(response.data.Title).to.equal('The title')

    it 'pulls body out into data key if body is a scalar payload', ->
      defop output:
        type: 'structure'
        payload: 'Body'
        members:
          Body: location: 'body', type: 'binary'

      extractData 'foobar'
      expect(response.error).to.equal(null)
      expect(response.data.Body).to.equal('foobar')

    it 'pulls body out into data key if body is a structure payload', ->
      defop output:
        type: 'structure'
        payload: 'Body'
        members:
          Body:
            shape: 'structureshape'

      extractData '{"a": "foo", "b": "bar"}'
      expect(response.error).to.equal(null)
      expect(response.data.Body).to.eql({a: 'foo', b: 'bar'})

    it 'pulls body out as Buffer if body is streaming payload', ->
      defop output:
        type: 'structure'
        payload: 'Body'
        members:
          Body: location: 'body', type: 'binary', streaming: true

      extractData 'foobar'
      expect(response.error).to.equal(null)
      expect(Buffer.isBuffer(response.data.Body)).to.equal(true)
      expect(response.data.Body.toString()).to.equal('foobar')

    it 'returns an empty object when the body is an empty string', ->
      extractData ''
      expect(response.error).to.equal(null)
      expect(response.data).to.eql({})

    it 'returns an empty object when the body is null', ->
      extractData ''
      expect(response.error).to.equal(null)
      expect(response.data).to.eql({})
