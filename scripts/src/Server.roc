import cli.Tcp
import Script

## A small loopback HTTP server for exactly one content-addressed platform bundle.
## Each accepted stream is closed when its final Roc reference leaves scope.
Server := [].{

	## Use an OS-assigned port so parallel CI runs cannot compete for a fixed port.
	listen! = || Tcp.listen!("127.0.0.1", 0, 5_000)

	## Service one request, returning 404 when it names any other artifact.
	respond! : Tcp.Stream, Str, List(U8) => Try({}, _)
	respond! = |stream, name, bytes| {
		request = stream.read_line!(65_536, 5_000)?
		read_headers!(stream, 0)?
		if request == "GET /${name} HTTP/1.1\r\n" or request == "GET /${name} HTTP/1.0\r\n" {
			stream.write_utf8!(headers("200 OK", bytes.len()), 5_000)?
			stream.write!(bytes, 30_000)
		} else {
			stream.write_utf8!(headers("404 Not Found", 0), 5_000)
		}
	}

	## Alternate child polling with serving requests; no shell, threads, or daemon.
	## The managed Child cancels and reaps on final release if servicing fails.
	wait! = |child, listener, name, bytes| {
		match child.try_wait!().map_err(|err| ChildWaitFailed(err))? {
			[output] => Ok(output)
			[_, _, ..] => Err(UnexpectedChildWaitResult)
			[] => match listener.accept!(100) {
				Ok(stream) => {
					respond!(stream, name, bytes)?
					wait!(child, listener, name, bytes)
				}
				Err(TcpListenErr(TimedOut)) => wait!(child, listener, name, bytes)
				Err(err) => Err(BundleServeFailed(err))
			}
		}
	}

	## Keep serving for the documented manual consumer workflow until interrupted.
	forever! = |listener, name, bytes| {
		match listener.accept!(1_000) {
			Ok(stream) => {
				respond!(stream, name, bytes)?
				forever!(listener, name, bytes)
			}
			Err(TcpListenErr(TimedOut)) => forever!(listener, name, bytes)
			Err(err) => Err(BundleServeFailed(err))
		}
	}
}

## Consume headers before closing a connection to avoid resetting an unread socket.
read_headers! = |stream, count| {
	if count >= 100 {
		return Err(TooManyHttpHeaders)
	}
	line = stream.read_line!(65_536, 5_000)?
	if line == "\r\n" or line == "\n" {
		Ok({})
	} else {
		read_headers!(stream, count + 1)
	}
}

## HTTP headers require CRLF separators and an exact byte length for the body.
headers : Str, U64 -> Str
headers = |status, length|
	Str.join_with(["HTTP/1.1 ${status}", "Content-Type: application/octet-stream", "Content-Length: ${length.to_str()}", "Connection: close", "", ""], "\r\n")
