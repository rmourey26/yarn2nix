const {normalize} = require('path')
const [,,derivationBinPath,nodeModules,...packagesToPublishBin] = process.argv
packagesToPublishBin.forEach(name => {
    const packagePath = `${nodeModules}/${name}`
    const {bin} = require(`${packagePath}/package.json`)
    // const bins = typeof bin === 'string' ? { [name]: bin } : bin
    const bins = {
        string: { [name]: bin },
        object: bin,
        undefined: {}
    }[typeof bin]
    Object.entries(bins).forEach(([binName, binPath]) => {
        const normalizedBinName = binName.replace('@', "").replace('/', '-')
        const targetPath = normalize(`${packagePath}/${binPath}`)
        const createdPath = `${derivationBinPath}/${normalizedBinName}`
        console.log(`${targetPath} ${createdPath}`);
    })
})
