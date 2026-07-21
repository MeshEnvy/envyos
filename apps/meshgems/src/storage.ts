export class PortIndependentStorage {
  private static readonly STORAGE_KEY = 'meshgems_composer_data'

  private static getStorageMethods(): Storage[] {
    const methods: Storage[] = []
    try {
      if (typeof localStorage !== 'undefined') methods.push(localStorage)
    } catch {
      /* ignore */
    }
    try {
      if (typeof sessionStorage !== 'undefined') methods.push(sessionStorage)
    } catch {
      /* ignore */
    }
    return methods
  }

  static save(data: unknown): boolean {
    for (const storage of this.getStorageMethods()) {
      try {
        storage.setItem(this.STORAGE_KEY, JSON.stringify(data))
        return true
      } catch {
        /* try next */
      }
    }
    return false
  }

  static load(): unknown | null {
    for (const storage of this.getStorageMethods()) {
      try {
        const data = JSON.parse(storage.getItem(this.STORAGE_KEY) || 'null')
        if (data) return data
      } catch {
        /* try next */
      }
    }
    return null
  }
}
