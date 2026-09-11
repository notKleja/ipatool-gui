import Foundation
import Darwin

/// A pseudo-terminal pair used to feed secrets to ipatool's `term.ReadPassword`, which requires a TTY.
/// Echo is disabled on the slave so nothing typed is ever mirrored back.
struct PseudoTerminal: Sendable {
    let masterDescriptor: Int32
    let slaveDescriptor: Int32

    struct OpenError: Error {}

    static func open() throws -> PseudoTerminal {
        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else { throw OpenError() }
        var attributes = termios()
        if tcgetattr(slave, &attributes) == 0 {
            attributes.c_lflag &= ~UInt(ECHO | ECHOE | ECHOK | ECHONL)
            attributes.c_lflag |= UInt(ICANON)
            tcsetattr(slave, TCSANOW, &attributes)
        }
        _ = fcntl(master, F_SETFD, FD_CLOEXEC)
        return PseudoTerminal(masterDescriptor: master, slaveDescriptor: slave)
    }

    func closeSlave() { close(slaveDescriptor) }
    func closeMaster() { close(masterDescriptor) }
}
