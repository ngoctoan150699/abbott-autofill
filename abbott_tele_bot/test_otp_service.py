"""Kiểm thử offline: python test_otp_service.py."""
from unittest.mock import patch
from otp_service import OtpService

class Response:
    def __init__(self, status, payload):
        self.status_code, self.payload = status, payload
    def json(self):
        return self.payload

with patch('otp_service.requests.get', return_value=Response(200, {'data': {'status': 'pending'}})):
    assert OtpService.check_otp('hupsms', 'token', 'id')[0] == 'pending'
with patch('otp_service.requests.get', return_value=Response(200, {'data': {'smsContent': 'Abbott code 123456'}})):
    assert OtpService.check_otp('hupsms', 'token', 'id')[:2] == ('success', '123456')
with patch('otp_service.requests.get', return_value=Response(401, {})):
    assert OtpService.check_otp('hupsms', 'token', 'id')[0] == 'error'
with patch('otp_service.requests.get', return_value=Response(200, {'success': False})):
    assert not OtpService.cancel_rental('hupsms', 'token', 'id')[0]
with patch('otp_service.requests.get', return_value=Response(200, {'success': True, 'data': {'refund': 1500}})):
    assert '1500' in OtpService.cancel_rental('hupsms', 'token', 'id')[1]
print('OTP checks OK')

