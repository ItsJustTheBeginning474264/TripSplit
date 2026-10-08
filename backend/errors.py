"""Application-level exceptions. They carry an HTTP status so the Flask error handler
can turn any of them into a consistent JSON response."""


class ApiError(Exception):
    status_code = 400

    def __init__(self, message, status_code=None, details=None):
        super().__init__(message)
        self.message = message
        if status_code is not None:
            self.status_code = status_code
        self.details = details

    def to_dict(self):
        body = {"error": self.message}
        if self.details:
            body["details"] = self.details
        return body


class ValidationError(ApiError):
    status_code = 400


class AuthError(ApiError):
    status_code = 401


class ForbiddenError(ApiError):
    status_code = 403


class NotFoundError(ApiError):
    status_code = 404


class ConflictError(ApiError):
    status_code = 409
